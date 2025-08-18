"""Community vocabulary database API client for the Seed service.

This module provides functionality to interact with the Phoenix server's community
vocabulary endpoints, allowing the text analysis pipeline to query existing vocabulary
and contribute new vocabulary discoveries back to the community database.
"""

import asyncio
import time
from collections import OrderedDict, deque
from datetime import datetime
from urllib.parse import urljoin

import aiohttp

from .config import get_config
from .logger import get_logger
from .text_analysis_schema import TextAnalysisOutput

logger = get_logger(__name__)


class TTLCache:
    """Simple TTL (Time To Live) cache with LRU eviction and size bounds."""

    def __init__(self, max_size: int = 1000, ttl: float = 300.0):
        """
        Initialize TTL cache.

        Args:
            max_size: Maximum number of items to cache
            ttl: Time to live in seconds
        """
        self.max_size = max_size
        self.ttl = ttl
        self._cache = OrderedDict()

    def get(self, key: str):
        """Get item from cache if not expired."""
        if key not in self._cache:
            return None

        timestamp, value = self._cache[key]
        current_time = time.time()

        # Check if expired
        if current_time - timestamp > self.ttl:
            del self._cache[key]
            return None

        # Move to end (LRU)
        self._cache.move_to_end(key)
        return value

    def set(self, key: str, value) -> None:
        """Set item in cache with current timestamp."""
        current_time = time.time()

        if key in self._cache:
            # Update existing item
            self._cache[key] = (current_time, value)
            self._cache.move_to_end(key)
        else:
            # Add new item
            self._cache[key] = (current_time, value)

            # Evict oldest if over size limit
            while len(self._cache) > self.max_size:
                self._cache.popitem(last=False)  # Remove oldest

    def clear(self) -> None:
        """Clear all cached items."""
        self._cache.clear()

    def size(self) -> int:
        """Get current cache size."""
        return len(self._cache)

    def cleanup_expired(self) -> int:
        """Remove expired items and return count of removed items."""
        current_time = time.time()
        expired_keys = []

        for key, (timestamp, _) in self._cache.items():
            if current_time - timestamp > self.ttl:
                expired_keys.append(key)

        for key in expired_keys:
            del self._cache[key]

        return len(expired_keys)


class RateLimiter:
    """Token bucket rate limiter for API requests."""

    def __init__(self, max_requests: int = 100, time_window: float = 60.0):
        """
        Initialize rate limiter.

        Args:
            max_requests: Maximum requests allowed in time window
            time_window: Time window in seconds
        """
        self.max_requests = max_requests
        self.time_window = time_window
        self.requests: deque = deque()
        self._lock = asyncio.Lock()

    async def acquire(self) -> bool:
        """
        Acquire permission to make a request.

        Returns:
            True if request is allowed, False if rate limited
        """
        async with self._lock:
            current_time = time.time()

            # Remove expired requests from window
            while self.requests and current_time - self.requests[0] > self.time_window:
                self.requests.popleft()

            # Check if we can make a new request
            if len(self.requests) < self.max_requests:
                self.requests.append(current_time)
                return True

            return False

    async def wait_and_acquire(self, max_wait: float = 10.0) -> bool:
        """
        Wait for rate limit to allow request.

        Args:
            max_wait: Maximum time to wait in seconds

        Returns:
            True if request was acquired, False if timeout
        """
        start_time = time.time()

        while time.time() - start_time < max_wait:
            if await self.acquire():
                return True

            # Wait a bit before retrying
            await asyncio.sleep(0.1)

        return False

    def get_stats(self) -> dict[str, any]:
        """Get current rate limiter statistics."""
        current_time = time.time()

        # Clean expired requests
        while self.requests and current_time - self.requests[0] > self.time_window:
            self.requests.popleft()

        return {
            "current_requests": len(self.requests),
            "max_requests": self.max_requests,
            "time_window": self.time_window,
            "utilization": len(self.requests) / self.max_requests,
        }


class CommunityAPIError(Exception):
    """Exception raised for community API related errors."""

    pass


class CommunityVocabularyClient:
    """Client for interacting with community vocabulary database."""

    def __init__(self, api_url: str | None = None, rate_limit: int = 100, rate_window: float = 60.0):
        """Initialize the community API client.

        Args:
            api_url: Base URL for the Phoenix server API
            rate_limit: Maximum requests per time window
            rate_window: Rate limit time window in seconds
        """
        config = get_config()
        self.api_url = api_url or config.websocket.server_url
        self.session: aiohttp.ClientSession | None = None

        # Request configuration
        self.timeout = aiohttp.ClientTimeout(total=10)
        self.max_retries = 3
        self.retry_delay = 0.5

        # Rate limiting
        self.rate_limiter = RateLimiter(max_requests=rate_limit, time_window=rate_window)

    async def __aenter__(self):
        """Async context manager entry."""
        headers = {
            "User-Agent": "Landale-Seed/1.0 (Community-Integration)",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

        self.session = aiohttp.ClientSession(timeout=self.timeout, headers=headers)
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def _make_request(
        self, method: str, endpoint: str, params: dict | None = None, json_data: dict | None = None
    ) -> dict:
        """Make a request to the community API with rate limiting.

        Args:
            method: HTTP method (GET, POST, etc.)
            endpoint: API endpoint to call
            params: Optional query parameters
            json_data: Optional JSON data for POST requests

        Returns:
            JSON response as dictionary

        Raises:
            CommunityAPIError: On API errors or failures
        """
        if not self.session:
            raise CommunityAPIError("Session not initialized - use async context manager")

        # Apply rate limiting
        if not await self.rate_limiter.wait_and_acquire(max_wait=5.0):
            raise CommunityAPIError("Rate limit exceeded - request could not be processed")

        url = urljoin(f"{self.api_url}/api/", endpoint.lstrip("/"))

        for attempt in range(self.max_retries):
            try:
                logger.debug("Making community API request", method=method, url=url, attempt=attempt + 1)

                kwargs = {"params": params} if params else {}
                if json_data:
                    kwargs["json"] = json_data

                async with self.session.request(method, url, **kwargs) as response:
                    if response.status == 200:
                        data = await response.json()
                        logger.debug("Community API request successful", url=url, status=response.status)
                        return data

                    elif response.status == 201:  # Created
                        data = await response.json()
                        logger.debug("Community API create successful", url=url, status=response.status)
                        return data

                    elif response.status == 404:
                        logger.debug("Community API resource not found", url=url)
                        return {"data": []}  # Return empty data for not found

                    elif response.status >= 500:
                        logger.warning("Community API server error", status=response.status, attempt=attempt + 1)
                        if attempt < self.max_retries - 1:
                            await asyncio.sleep(self.retry_delay * (2**attempt))
                            continue
                        raise CommunityAPIError(f"Server error: HTTP {response.status}")

                    else:
                        error_text = await response.text()
                        logger.error("Community API client error", status=response.status, error=error_text)
                        raise CommunityAPIError(f"Client error: HTTP {response.status}")

            except aiohttp.ClientError as e:
                logger.error("Network error making community API request", url=url, error=str(e), attempt=attempt + 1)
                if attempt < self.max_retries - 1:
                    await asyncio.sleep(self.retry_delay * (2**attempt))
                    continue
                raise CommunityAPIError(f"Network error: {e}") from e

        raise CommunityAPIError(f"Failed after {self.max_retries} attempts")

    async def search_vocabulary(self, query: str, limit: int = 25) -> list[dict]:
        """Search for existing vocabulary entries.

        Args:
            query: Search query (phrase or definition)
            limit: Maximum number of results

        Returns:
            List of vocabulary entry dictionaries
        """
        params = {"q": query, "limit": limit}

        try:
            data = await self._make_request("GET", "/community/vocabulary/search", params)
            vocabulary_entries = data.get("data", [])

            logger.debug("Searched vocabulary", query=query, count=len(vocabulary_entries), limit=limit)
            return vocabulary_entries

        except CommunityAPIError as e:
            logger.error("Failed to search vocabulary", query=query, error=str(e))
            return []  # Return empty list on error

    async def get_vocabulary_by_category(self, category: str, limit: int = 50) -> list[dict]:
        """Get vocabulary entries by category.

        Args:
            category: Vocabulary category (meme, inside_joke, etc.)
            limit: Maximum number of results

        Returns:
            List of vocabulary entry dictionaries
        """
        params = {"category": category, "limit": limit}

        try:
            data = await self._make_request("GET", "/community/vocabulary", params)
            vocabulary_entries = data.get("data", [])

            logger.debug(
                "Retrieved vocabulary by category", category=category, count=len(vocabulary_entries), limit=limit
            )
            return vocabulary_entries

        except CommunityAPIError as e:
            logger.error("Failed to get vocabulary by category", category=category, error=str(e))
            return []

    async def get_popular_vocabulary(self, limit: int = 20) -> list[dict]:
        """Get popular vocabulary entries.

        Args:
            limit: Maximum number of results

        Returns:
            List of vocabulary entry dictionaries
        """
        params = {"type": "popular", "limit": limit}

        try:
            data = await self._make_request("GET", "/community/vocabulary", params)
            vocabulary_entries = data.get("data", [])

            logger.debug("Retrieved popular vocabulary", count=len(vocabulary_entries), limit=limit)
            return vocabulary_entries

        except CommunityAPIError as e:
            logger.error("Failed to get popular vocabulary", error=str(e))
            return []

    async def create_vocabulary_entry(
        self, phrase: str, category: str, definition: str = None, context: str = None, tags: list[str] = None
    ) -> dict | None:
        """Create a new vocabulary entry.

        Args:
            phrase: The vocabulary phrase
            category: Category (meme, inside_joke, catchphrase, etc.)
            definition: Optional definition
            context: Optional context information
            tags: Optional list of tags

        Returns:
            Created vocabulary entry dictionary or None if failed
        """
        json_data = {"phrase": phrase, "category": category}

        if definition:
            json_data["definition"] = definition
        if context:
            json_data["context"] = context
        if tags:
            json_data["tags"] = tags

        try:
            data = await self._make_request("POST", "/community/vocabulary", json_data=json_data)
            vocabulary_entry = data.get("data", {})

            logger.info(
                "Created vocabulary entry", phrase=phrase, category=category, entry_id=vocabulary_entry.get("id")
            )
            return vocabulary_entry

        except CommunityAPIError as e:
            logger.error("Failed to create vocabulary entry", phrase=phrase, category=category, error=str(e))
            return None

    async def increment_vocabulary_usage(self, phrase: str) -> bool:
        """Increment usage count for existing vocabulary.

        Note: This would require a new API endpoint in Phoenix server.
        For now, we'll log the usage and return success.

        Args:
            phrase: The vocabulary phrase that was used

        Returns:
            True if successful, False otherwise
        """
        # TODO: Implement when Phoenix server adds increment endpoint
        logger.debug("Vocabulary usage tracked", phrase=phrase)
        return True

    def get_rate_limit_stats(self) -> dict[str, any]:
        """Get current rate limiter statistics."""
        return self.rate_limiter.get_stats()


class CommunityVocabularyIntegrator:
    """Integrates vocabulary extraction with community database."""

    def __init__(self, cache_size: int = 1000, cache_ttl: float = 300.0):
        """
        Initialize integrator with TTL cache.

        Args:
            cache_size: Maximum number of items to cache
            cache_ttl: Cache TTL in seconds (default 5 minutes)
        """
        self.client = CommunityVocabularyClient()
        self.vocabulary_cache = TTLCache(max_size=cache_size, ttl=cache_ttl)
        self.stats_cache = TTLCache(max_size=100, ttl=cache_ttl * 2)  # Longer TTL for stats

        # Categories for different types of detected vocabulary
        self.category_mapping = {
            "gaming_term": "catchphrase",
            "community_phrase": "inside_joke",
            "repeated_phrase": "meme",
            "emote_phrase": "emote_phrase",
            "reference": "reference",
            "slang": "slang",
        }

    async def enhance_vocabulary_extraction(self, analysis_output: TextAnalysisOutput) -> TextAnalysisOutput:
        """Enhance vocabulary extraction results with community database context.

        Args:
            analysis_output: Original text analysis output

        Returns:
            Enhanced analysis output with community vocabulary context
        """
        try:
            async with self.client:
                # Check existing vocabulary matches against community database
                enhanced_matches = await self._validate_vocabulary_matches(analysis_output.vocabulary_matches)

                # Categorize potential vocabulary using community context
                categorized_potential = await self._categorize_potential_vocabulary(
                    analysis_output.potential_vocabulary
                )

                # Update analysis output with enhanced data
                analysis_output.vocabulary_matches = enhanced_matches
                analysis_output.potential_vocabulary = categorized_potential

                # Add community context metadata
                if not hasattr(analysis_output, "community_context"):
                    analysis_output.community_context = {}

                analysis_output.community_context.update(
                    {
                        "vocabulary_validated": len(enhanced_matches),
                        "potential_categorized": len(categorized_potential),
                        "processed_at": datetime.utcnow().isoformat(),
                    }
                )

                logger.debug(
                    "Enhanced vocabulary with community context",
                    input_id=analysis_output.input_id,
                    validated_matches=len(enhanced_matches),
                    categorized_potential=len(categorized_potential),
                )

            return analysis_output

        except Exception as e:
            logger.error(
                "Failed to enhance vocabulary with community context", input_id=analysis_output.input_id, error=str(e)
            )
            return analysis_output  # Return original on error

    async def contribute_vocabulary_discoveries(self, analysis_output: TextAnalysisOutput) -> dict:
        """Contribute new vocabulary discoveries back to community database.

        Args:
            analysis_output: Text analysis output with potential vocabulary

        Returns:
            Summary of contributions made
        """
        contributions = {"created": 0, "usage_tracked": 0, "errors": 0}

        try:
            async with self.client:
                # Process potential vocabulary for contribution
                for phrase_data in analysis_output.potential_vocabulary:
                    # Handle both string and dictionary formats for backward compatibility
                    if isinstance(phrase_data, str):
                        phrase = phrase_data
                        confidence = 0.75  # Default confidence for string format
                    else:
                        phrase = phrase_data.get("phrase", "")
                        confidence = phrase_data.get("confidence", 0.0)

                    # Only contribute high-confidence potential vocabulary
                    if confidence >= 0.7 and len(phrase) >= 3:
                        category = self._determine_phrase_category(phrase_data)
                        context = self._extract_phrase_context(analysis_output, phrase)

                        # Check if vocabulary already exists
                        existing = await self.client.search_vocabulary(phrase, limit=1)

                        if existing:
                            # Track usage of existing vocabulary
                            success = await self.client.increment_vocabulary_usage(phrase)
                            if success:
                                contributions["usage_tracked"] += 1
                        else:
                            # Create new vocabulary entry for high-confidence phrases
                            if confidence >= 0.8:  # Higher threshold for creation
                                entry = await self.client.create_vocabulary_entry(
                                    phrase=phrase, category=category, context=context
                                )
                                if entry:
                                    contributions["created"] += 1

                logger.info("Contributed vocabulary discoveries", input_id=analysis_output.input_id, **contributions)

        except Exception as e:
            logger.error("Failed to contribute vocabulary discoveries", input_id=analysis_output.input_id, error=str(e))
            contributions["errors"] += 1

        return contributions

    async def _validate_vocabulary_matches(self, vocabulary_matches: list[dict]) -> list[dict]:
        """Validate vocabulary matches against community database with caching."""
        enhanced_matches = []

        for match in vocabulary_matches:
            phrase = match.get("phrase", "")
            if not phrase:
                continue

            # Check cache first
            cache_key = f"vocab:{phrase.lower()}"
            cached_result = self.vocabulary_cache.get(cache_key)

            if cached_result is not None:
                # Use cached result
                if cached_result:  # Not empty list
                    community_entry = cached_result[0]
                    enhanced_match = match.copy()
                    enhanced_match.update(
                        {
                            "community_verified": True,
                            "community_category": community_entry.get("category"),
                            "community_usage_count": community_entry.get("usage_count", 0),
                            "community_definition": community_entry.get("definition"),
                        }
                    )
                    enhanced_matches.append(enhanced_match)
                else:
                    # Cached negative result
                    match["community_verified"] = False
                    enhanced_matches.append(match)
            else:
                # Search for existing community vocabulary
                existing = await self.client.search_vocabulary(phrase, limit=1)

                # Cache the result (empty list for negative results)
                self.vocabulary_cache.set(cache_key, existing)

                if existing:
                    community_entry = existing[0]
                    # Enhance match with community context
                    enhanced_match = match.copy()
                    enhanced_match.update(
                        {
                            "community_verified": True,
                            "community_category": community_entry.get("category"),
                            "community_usage_count": community_entry.get("usage_count", 0),
                            "community_definition": community_entry.get("definition"),
                        }
                    )
                    enhanced_matches.append(enhanced_match)
                else:
                    # Mark as unverified but keep
                    match["community_verified"] = False
                    enhanced_matches.append(match)

        return enhanced_matches

    async def _categorize_potential_vocabulary(self, potential_vocabulary: list) -> list:
        """Categorize potential vocabulary using community context."""
        categorized = []

        for phrase_data in potential_vocabulary:
            # Handle both string and dictionary formats
            if isinstance(phrase_data, str):
                phrase = phrase_data
                enhanced_phrase = {"phrase": phrase, "confidence": 0.75, "pattern_type": "unknown"}
            else:
                phrase = phrase_data.get("phrase", "")
                enhanced_phrase = phrase_data.copy()

            if not phrase:
                continue

            # Search for similar vocabulary for context
            similar = await self.client.search_vocabulary(phrase, limit=3)

            # Use the enhanced_phrase we already created above
            if similar:
                # Add context from similar community vocabulary
                categories = [entry.get("category") for entry in similar]
                most_common_category = max(set(categories), key=categories.count) if categories else None

                enhanced_phrase["suggested_category"] = most_common_category
                enhanced_phrase["similar_count"] = len(similar)
                enhanced_phrase["community_context"] = True
            else:
                enhanced_phrase["community_context"] = False

            categorized.append(enhanced_phrase)

        return categorized

    def _determine_phrase_category(self, phrase_data) -> str:
        """Determine the best category for a phrase based on analysis data."""
        # Handle both string and dictionary formats
        if isinstance(phrase_data, str):
            return "slang"  # Default category for string format

        pattern_type = phrase_data.get("pattern_type", "unknown")
        suggested_category = phrase_data.get("suggested_category")

        # Use community suggestion if available
        if suggested_category:
            return suggested_category

        # Map analysis patterns to community categories
        return self.category_mapping.get(pattern_type, "slang")

    def _extract_phrase_context(self, analysis_output: TextAnalysisOutput, _phrase: str) -> str:
        """Extract context for a phrase from the analysis output."""
        context_parts = []

        # Add source information
        if hasattr(analysis_output, "source"):
            context_parts.append(f"Source: {analysis_output.source}")

        # Add username if available
        if hasattr(analysis_output, "username") and analysis_output.username:
            context_parts.append(f"User: {analysis_output.username}")

        # Add any additional context
        if hasattr(analysis_output, "context") and analysis_output.context:
            context_parts.append(analysis_output.context)

        return " | ".join(context_parts) if context_parts else "Auto-detected from text analysis"


# Convenience functions for external use


async def search_community_vocabulary(query: str, limit: int = 25) -> list[dict]:
    """Search community vocabulary database.

    Args:
        query: Search query
        limit: Maximum results

    Returns:
        List of vocabulary entries
    """
    async with CommunityVocabularyClient() as client:
        return await client.search_vocabulary(query, limit)


async def get_popular_community_vocabulary(limit: int = 20) -> list[dict]:
    """Get popular community vocabulary.

    Args:
        limit: Maximum results

    Returns:
        List of popular vocabulary entries
    """
    async with CommunityVocabularyClient() as client:
        return await client.get_popular_vocabulary(limit)


async def enhance_analysis_with_community_context(analysis_output: TextAnalysisOutput) -> TextAnalysisOutput:
    """Enhance text analysis with community vocabulary context.

    Args:
        analysis_output: Original analysis output

    Returns:
        Enhanced analysis output
    """
    integrator = CommunityVocabularyIntegrator()
    return await integrator.enhance_vocabulary_extraction(analysis_output)


async def contribute_analysis_to_community(analysis_output: TextAnalysisOutput) -> dict:
    """Contribute analysis discoveries to community database.

    Args:
        analysis_output: Analysis output with discoveries

    Returns:
        Summary of contributions
    """
    integrator = CommunityVocabularyIntegrator()
    return await integrator.contribute_vocabulary_discoveries(analysis_output)
