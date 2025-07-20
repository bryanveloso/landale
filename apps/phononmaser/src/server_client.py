"""HTTP client for sending transcriptions to Phoenix server."""

from datetime import datetime
from zoneinfo import ZoneInfo

import aiohttp

from events import TranscriptionEvent
from logger import get_logger
from timestamp_utils import convert_timestamp_to_iso

logger = get_logger(__name__)


class ServerTranscriptionClient:
    """Client for sending transcriptions to Phoenix server."""

    def __init__(self, server_url: str = "http://localhost:7175"):
        self.server_url = server_url.rstrip("/")
        self.transcription_endpoint = f"{self.server_url}/api/transcriptions"
        self.session: aiohttp.ClientSession | None = None

        # Generate daily session ID using Los Angeles timezone
        la_tz = ZoneInfo("America/Los_Angeles")
        today = datetime.now(la_tz).strftime("%Y_%m_%d")
        self.stream_session_id = f"stream_{today}"

    async def __aenter__(self):
        """Async context manager entry."""
        connector = aiohttp.TCPConnector(limit=10, limit_per_host=5, keepalive_timeout=30, enable_cleanup_closed=True)
        self.session = aiohttp.ClientSession(connector=connector, timeout=aiohttp.ClientTimeout(total=10, connect=5))
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def send_transcription(self, event: TranscriptionEvent) -> bool:
        """
        Send transcription event to Phoenix server.

        Args:
            event: TranscriptionEvent from phononmaser

        Returns:
            bool: True if successfully sent, False otherwise
        """
        if not self.session:
            logger.error("HTTP session not initialized")
            return False

        try:
            payload = {
                "timestamp": convert_timestamp_to_iso(event.timestamp),
                "duration": event.duration,
                "text": event.text,
                "source_id": "phononmaser",
                "stream_session_id": self.stream_session_id,
                "confidence": None,  # whisper.cpp doesn't provide confidence scores
                "metadata": {"original_timestamp_us": event.timestamp, "source": "whisper_cpp", "language": "en"},
            }

            headers = {"Content-Type": "application/json", "User-Agent": "phononmaser/1.0"}

            async with self.session.post(self.transcription_endpoint, json=payload, headers=headers) as response:
                if response.status == 201:
                    logger.debug(f"Transcription sent successfully: {event.text[:50]}...")
                    return True
                elif response.status == 422:
                    # Validation error - log details
                    try:
                        error_data = await response.json()
                        logger.warning(f"Transcription validation failed: {error_data}")
                    except Exception:
                        logger.warning(f"Transcription validation failed: HTTP {response.status}")
                    return False
                else:
                    logger.warning(f"Unexpected response from server: HTTP {response.status}")
                    return False

        except aiohttp.ClientError as e:
            logger.warning(f"HTTP client error sending transcription: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error sending transcription: {e}")
            return False

    async def health_check(self) -> bool:
        """
        Check if the Phoenix server is reachable.

        Returns:
            bool: True if server is healthy, False otherwise
        """
        if not self.session:
            return False

        try:
            health_url = f"{self.server_url}/health"
            async with self.session.get(health_url) as response:
                return response.status == 200
        except Exception as e:
            logger.debug(f"Server health check failed: {e}")
            return False
