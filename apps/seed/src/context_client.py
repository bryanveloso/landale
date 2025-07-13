"""HTTP client for posting contexts to the Phoenix server."""

import logging
from datetime import datetime
from typing import Any

import aiohttp

from .service_config import ServiceConfig

logger = logging.getLogger(__name__)


class ContextClient:
    """HTTP client for posting context data to the Phoenix server."""

    def __init__(self, server_url: str | None = None):
        self.server_url = server_url or ServiceConfig.get_url("server")
        self.session: aiohttp.ClientSession | None = None

    async def __aenter__(self):
        """Async context manager entry."""
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30))
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def create_context(self, context_data: dict[str, Any]) -> bool:
        """
        Create a new context entry in the Phoenix server.

        Args:
            context_data: Dictionary containing context information:
                - started: datetime - Context start time
                - ended: datetime - Context end time
                - session: str - Stream session ID
                - transcript: str - Aggregated transcript text
                - duration: float - Context duration in seconds
                - chat: dict (optional) - Chat activity summary
                - interactions: dict (optional) - Viewer interaction events
                - emotes: dict (optional) - Emote usage statistics
                - patterns: dict (optional) - AI-detected patterns
                - sentiment: str (optional) - Overall sentiment
                - topics: list (optional) - Extracted topics

        Returns:
            bool: True if successful, False otherwise
        """
        if not self.session:
            logger.error("HTTP session not initialized")
            return False

        try:
            # Format datetime fields to ISO format
            formatted_data = self._format_context_data(context_data)

            url = f"{self.server_url}/api/contexts"

            async with self.session.post(url, json=formatted_data) as response:
                if response.status == 201:
                    result = await response.json()
                    logger.info(f"Context created successfully: {result.get('data', {}).get('started')}")
                    return True
                elif response.status == 422:
                    error_data = await response.json()
                    logger.error(f"Context validation failed: {error_data.get('errors', {})}")
                    return False
                else:
                    error_text = await response.text()
                    logger.error(f"Failed to create context: HTTP {response.status} - {error_text}")
                    return False

        except aiohttp.ClientError as e:
            logger.error(f"HTTP client error creating context: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error creating context: {e}")
            return False

    def _format_context_data(self, data: dict[str, Any]) -> dict[str, Any]:
        """Format context data for HTTP transmission."""
        formatted = data.copy()

        # Convert datetime objects to ISO format strings
        if "started" in formatted and isinstance(formatted["started"], datetime):
            formatted["started"] = formatted["started"].isoformat()

        if "ended" in formatted and isinstance(formatted["ended"], datetime):
            formatted["ended"] = formatted["ended"].isoformat()

        # Ensure required fields are present
        required_fields = ["started", "ended", "session", "transcript", "duration"]
        for field in required_fields:
            if field not in formatted:
                raise ValueError(f"Required field '{field}' missing from context data")

        # Validate optional fields
        if "sentiment" in formatted and formatted["sentiment"] not in ["positive", "negative", "neutral"]:
            logger.warning(f"Invalid sentiment value: {formatted['sentiment']}, removing")
            del formatted["sentiment"]

        if "topics" in formatted and not isinstance(formatted["topics"], list):
            logger.warning(f"Topics must be a list, got {type(formatted['topics'])}, removing")
            del formatted["topics"]

        return formatted

    async def get_contexts(self, limit: int = 50, session: str | None = None) -> list[dict[str, Any]] | None:
        """
        Retrieve contexts from the Phoenix server.

        Args:
            limit: Maximum number of results
            session: Optional session filter

        Returns:
            List of context dictionaries or None if failed
        """
        if not self.session:
            logger.error("HTTP session not initialized")
            return None

        try:
            params = {"limit": limit}
            if session:
                params["session"] = session

            url = f"{self.server_url}/api/contexts"

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    result = await response.json()
                    return result.get("data", [])
                else:
                    error_text = await response.text()
                    logger.error(f"Failed to get contexts: HTTP {response.status} - {error_text}")
                    return None

        except Exception as e:
            logger.error(f"Error getting contexts: {e}")
            return None

    async def search_contexts(
        self, query: str, limit: int = 25, session: str | None = None
    ) -> list[dict[str, Any]] | None:
        """
        Search contexts by transcript content.

        Args:
            query: Search query string
            limit: Maximum number of results
            session: Optional session filter

        Returns:
            List of matching context dictionaries or None if failed
        """
        if not self.session:
            logger.error("HTTP session not initialized")
            return None

        try:
            params = {"q": query, "limit": limit}
            if session:
                params["session"] = session

            url = f"{self.server_url}/api/contexts/search"

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    result = await response.json()
                    return result.get("data", [])
                else:
                    error_text = await response.text()
                    logger.error(f"Failed to search contexts: HTTP {response.status} - {error_text}")
                    return None

        except Exception as e:
            logger.error(f"Error searching contexts: {e}")
            return None

    async def get_context_stats(self, hours: int = 24) -> dict[str, Any] | None:
        """
        Get context statistics.

        Args:
            hours: Time window in hours

        Returns:
            Statistics dictionary or None if failed
        """
        if not self.session:
            logger.error("HTTP session not initialized")
            return None

        try:
            params = {"hours": hours}
            url = f"{self.server_url}/api/contexts/stats"

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    result = await response.json()
                    return result.get("data", {})
                else:
                    error_text = await response.text()
                    logger.error(f"Failed to get context stats: HTTP {response.status} - {error_text}")
                    return None

        except Exception as e:
            logger.error(f"Error getting context stats: {e}")
            return None
