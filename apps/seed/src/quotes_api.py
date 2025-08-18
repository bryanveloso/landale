"""Elsydeon quotes API integration for importing historical quote data.

This module provides functionality to fetch quotes from an external quotes database
and convert them into the standardized TextAnalysisInput format for processing
through the text analysis pipeline.
"""

import asyncio
from collections.abc import AsyncGenerator
from datetime import datetime, timedelta
from urllib.parse import urljoin

import aiohttp

from .logger import get_logger
from .text_analysis_schema import TextAnalysisInput, create_quote_input

logger = get_logger(__name__)


class QuotesAPIError(Exception):
    """Exception raised for quotes API related errors."""

    pass


class ElsydeonQuotesClient:
    """Client for fetching quotes from the Elsydeon quotes API."""

    def __init__(self, api_url: str | None = None, api_key: str | None = None):
        """Initialize the quotes API client.

        Args:
            api_url: Base URL for the quotes API
            api_key: Optional API key for authentication
        """
        # Use environment variables for Elsydeon API configuration
        import os

        self.api_url = api_url or os.getenv("ELSYDEON_API_URL", "http://saya:3000/api")
        self.api_key = api_key or os.getenv("ELSYDEON_API_KEY")
        self.session: aiohttp.ClientSession | None = None

        # Request configuration
        self.timeout = aiohttp.ClientTimeout(total=30)
        self.max_retries = 3
        self.retry_delay = 1.0

        # Rate limiting to be respectful to the API
        self.requests_per_minute = 60
        self.request_interval = 60.0 / self.requests_per_minute
        self._last_request_time = 0.0

    async def __aenter__(self):
        """Async context manager entry."""
        headers = {
            "User-Agent": "Landale-Seed/1.0 (Streaming-Analytics)",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        self.session = aiohttp.ClientSession(timeout=self.timeout, headers=headers)
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def _rate_limit(self):
        """Implement rate limiting for API requests."""
        now = datetime.utcnow().timestamp()
        time_since_last = now - self._last_request_time

        if time_since_last < self.request_interval:
            sleep_time = self.request_interval - time_since_last
            await asyncio.sleep(sleep_time)

        self._last_request_time = datetime.utcnow().timestamp()

    async def _make_request(self, endpoint: str, params: dict | None = None) -> dict:
        """Make a rate-limited request to the quotes API.

        Args:
            endpoint: API endpoint to call
            params: Optional query parameters

        Returns:
            JSON response as dictionary

        Raises:
            QuotesAPIError: On API errors or failures
        """
        if not self.session:
            raise QuotesAPIError("Session not initialized - use async context manager")

        await self._rate_limit()

        url = urljoin(self.api_url, endpoint)

        for attempt in range(self.max_retries):
            try:
                logger.debug("Making quotes API request", url=url, params=params, attempt=attempt + 1)

                async with self.session.get(url, params=params) as response:
                    if response.status == 200:
                        data = await response.json()
                        logger.debug("Quotes API request successful", url=url, status=response.status)
                        return data

                    elif response.status == 429:  # Rate limited
                        retry_after = int(response.headers.get("Retry-After", 60))
                        logger.warning("Rate limited by quotes API", retry_after=retry_after)
                        await asyncio.sleep(retry_after)
                        continue

                    elif response.status == 404:
                        logger.warning("Quotes API endpoint not found", url=url)
                        raise QuotesAPIError(f"Endpoint not found: {endpoint}")

                    elif response.status >= 500:
                        logger.warning("Quotes API server error", status=response.status, attempt=attempt + 1)
                        if attempt < self.max_retries - 1:
                            await asyncio.sleep(self.retry_delay * (2**attempt))
                            continue
                        raise QuotesAPIError(f"Server error: HTTP {response.status}")

                    else:
                        error_text = await response.text()
                        logger.error("Quotes API client error", status=response.status, error=error_text)
                        raise QuotesAPIError(f"Client error: HTTP {response.status}")

            except aiohttp.ClientError as e:
                logger.error("Network error making quotes API request", url=url, error=str(e), attempt=attempt + 1)
                if attempt < self.max_retries - 1:
                    await asyncio.sleep(self.retry_delay * (2**attempt))
                    continue
                raise QuotesAPIError(f"Network error: {e}") from e

        raise QuotesAPIError(f"Failed after {self.max_retries} attempts")

    async def get_recent_quotes(self, limit: int = 100, days: int = 30) -> list[dict]:
        """Fetch recent quotes from the API.

        Args:
            limit: Maximum number of quotes to fetch
            days: Number of days back to search

        Returns:
            List of quote dictionaries
        """
        since_date = datetime.utcnow() - timedelta(days=days)
        params = {"limit": limit, "since": since_date.isoformat(), "order": "created_desc"}

        try:
            data = await self._make_request("/quotes", params)
            quotes = data.get("quotes", [])

            logger.info("Fetched recent quotes", count=len(quotes), limit=limit, days=days)
            return quotes

        except QuotesAPIError as e:
            logger.error("Failed to fetch recent quotes", error=str(e))
            raise

    async def get_quotes_by_user(self, username: str, limit: int = 50) -> list[dict]:
        """Fetch quotes by a specific user.

        Args:
            username: Username to search for
            limit: Maximum number of quotes to fetch

        Returns:
            List of quote dictionaries
        """
        params = {"username": username, "limit": limit, "order": "created_desc"}

        try:
            data = await self._make_request("/quotes/by_user", params)
            quotes = data.get("quotes", [])

            logger.info("Fetched quotes by user", username=username, count=len(quotes), limit=limit)
            return quotes

        except QuotesAPIError as e:
            logger.error("Failed to fetch quotes by user", username=username, error=str(e))
            raise

    async def search_quotes(self, query: str, limit: int = 50) -> list[dict]:
        """Search quotes by text content.

        Args:
            query: Search query
            limit: Maximum number of quotes to fetch

        Returns:
            List of quote dictionaries
        """
        params = {"q": query, "limit": limit, "order": "relevance_desc"}

        try:
            data = await self._make_request("/quotes/search", params)
            quotes = data.get("quotes", [])

            logger.info("Searched quotes", query=query, count=len(quotes), limit=limit)
            return quotes

        except QuotesAPIError as e:
            logger.error("Failed to search quotes", query=query, error=str(e))
            raise

    async def get_all_quotes(self, batch_size: int = 100) -> AsyncGenerator[list[dict]]:
        """Fetch all quotes in batches for bulk import.

        Args:
            batch_size: Number of quotes per batch

        Yields:
            Batches of quote dictionaries
        """
        offset = 0
        total_fetched = 0

        while True:
            params = {
                "limit": batch_size,
                "offset": offset,
                "order": "created_asc",  # Chronological order for import
            }

            try:
                data = await self._make_request("/quotes", params)
                quotes = data.get("quotes", [])

                if not quotes:
                    logger.info("Finished fetching all quotes", total=total_fetched)
                    break

                total_fetched += len(quotes)
                offset += batch_size

                logger.debug("Fetched quote batch", batch_size=len(quotes), offset=offset, total=total_fetched)

                yield quotes

            except QuotesAPIError as e:
                logger.error("Failed to fetch quote batch", offset=offset, error=str(e))
                raise


class QuotesDataProcessor:
    """Processes raw quotes data into standardized text analysis format."""

    def __init__(self):
        """Initialize the processor."""
        self.processed_count = 0
        self.error_count = 0

    def process_quote(self, quote_data: dict) -> TextAnalysisInput | None:
        """Process a single quote into TextAnalysisInput format.

        Args:
            quote_data: Raw quote data from API

        Returns:
            TextAnalysisInput or None if processing failed
        """
        try:
            # Extract required fields
            text = quote_data.get("text", "").strip()
            username = quote_data.get("username", "").strip()
            quote_id = str(quote_data.get("id", ""))

            if not text or not username or not quote_id:
                logger.warning(
                    "Quote missing required fields", quote_id=quote_id, has_text=bool(text), has_username=bool(username)
                )
                self.error_count += 1
                return None

            # Parse creation date
            original_date = None
            if "created_at" in quote_data:
                try:
                    original_date = datetime.fromisoformat(quote_data["created_at"].replace("Z", "+00:00"))
                except (ValueError, AttributeError) as e:
                    logger.warning(
                        "Failed to parse quote date", quote_id=quote_id, date=quote_data.get("created_at"), error=str(e)
                    )

            # Extract context/metadata
            context = quote_data.get("context", "")
            if quote_data.get("game"):
                context = f"Game: {quote_data['game']}" + (f" | {context}" if context else "")

            # Create standardized input
            text_input = create_quote_input(
                text=text, username=username, quote_id=quote_id, original_date=original_date, context=context or None
            )

            self.processed_count += 1
            logger.debug("Processed quote", quote_id=quote_id, username=username, text_length=len(text))

            return text_input

        except Exception as e:
            logger.error("Failed to process quote", quote_data=quote_data, error=str(e))
            self.error_count += 1
            return None

    def process_quotes_batch(self, quotes_data: list[dict]) -> list[TextAnalysisInput]:
        """Process a batch of quotes.

        Args:
            quotes_data: List of raw quote dictionaries

        Returns:
            List of processed TextAnalysisInput objects
        """
        processed_quotes = []

        for quote_data in quotes_data:
            processed_quote = self.process_quote(quote_data)
            if processed_quote:
                processed_quotes.append(processed_quote)

        logger.info(
            "Processed quotes batch",
            input_count=len(quotes_data),
            output_count=len(processed_quotes),
            total_processed=self.processed_count,
            total_errors=self.error_count,
        )

        return processed_quotes


# Convenience functions for external use


async def import_recent_quotes(limit: int = 100, days: int = 30) -> list[TextAnalysisInput]:
    """Import recent quotes for text analysis.

    Args:
        limit: Maximum number of quotes to import
        days: Number of days back to search

    Returns:
        List of TextAnalysisInput objects ready for processing
    """
    async with ElsydeonQuotesClient() as client:
        quotes_data = await client.get_recent_quotes(limit=limit, days=days)

    processor = QuotesDataProcessor()
    return processor.process_quotes_batch(quotes_data)


async def import_quotes_by_user(username: str, limit: int = 50) -> list[TextAnalysisInput]:
    """Import quotes by a specific user.

    Args:
        username: Username to import quotes for
        limit: Maximum number of quotes to import

    Returns:
        List of TextAnalysisInput objects ready for processing
    """
    async with ElsydeonQuotesClient() as client:
        quotes_data = await client.get_quotes_by_user(username=username, limit=limit)

    processor = QuotesDataProcessor()
    return processor.process_quotes_batch(quotes_data)


async def search_and_import_quotes(query: str, limit: int = 50) -> list[TextAnalysisInput]:
    """Search and import quotes matching a query.

    Args:
        query: Search query
        limit: Maximum number of quotes to import

    Returns:
        List of TextAnalysisInput objects ready for processing
    """
    async with ElsydeonQuotesClient() as client:
        quotes_data = await client.search_quotes(query=query, limit=limit)

    processor = QuotesDataProcessor()
    return processor.process_quotes_batch(quotes_data)


async def bulk_import_all_quotes(batch_size: int = 100) -> AsyncGenerator[list[TextAnalysisInput]]:
    """Bulk import all quotes for comprehensive analysis.

    Args:
        batch_size: Number of quotes to process per batch

    Yields:
        Batches of TextAnalysisInput objects ready for processing
    """
    processor = QuotesDataProcessor()

    async with ElsydeonQuotesClient() as client:
        async for quotes_batch in client.get_all_quotes(batch_size=batch_size):
            processed_batch = processor.process_quotes_batch(quotes_batch)
            if processed_batch:
                yield processed_batch

    logger.info("Bulk import completed", total_processed=processor.processed_count, total_errors=processor.error_count)
