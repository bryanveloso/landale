"""Username extraction and prompt generation for transcription context."""

import asyncio
import contextlib
import json
import time
from collections import defaultdict
from typing import Any

import aiohttp
from shared import safe_handler
from shared.logger import get_logger

logger = get_logger(__name__)


class PromptManager:
    """
    Manages username extraction from Phoenix chat API and prompt generation.

    Features:
    - Circuit breaker protection for API resilience
    - 30-second minimum polling intervals with configurable timing
    - Username frequency prioritization
    - 200-character prompt limit with iterative building
    - Graceful degradation - never blocks transcription
    - Comprehensive error handling and monitoring
    """

    def __init__(
        self,
        phoenix_base_url: str = "http://saya:7175",
        poll_interval_seconds: float = 30.0,
        prompt_max_chars: int = 200,
        lookback_minutes: int = 10,
        prompt_expiry_minutes: int = 5,
    ):
        """
        Initialize PromptManager.

        Args:
            phoenix_base_url: Base URL for Phoenix server
            poll_interval_seconds: Minimum time between API polls (≥30s)
            prompt_max_chars: Maximum characters in generated prompt (safety limit)
            lookback_minutes: How far back to look for chat messages
            prompt_expiry_minutes: How long to use cached prompts
        """
        self.phoenix_base_url = phoenix_base_url.rstrip("/")
        self.poll_interval = max(30.0, poll_interval_seconds)  # Enforce 30s minimum
        self.prompt_max_chars = prompt_max_chars
        self.lookback_minutes = lookback_minutes
        self.prompt_expiry_minutes = prompt_expiry_minutes

        # API endpoint for bulk chat events
        self.bulk_api_url = f"{self.phoenix_base_url}/api/activity/events/bulk"

        # HTTP session for connection reuse
        self.session: aiohttp.ClientSession | None = None

        # State management
        self.current_prompt = ""
        self.last_prompt_update = 0.0
        self.last_poll_time = 0.0
        self.running = False
        self.poll_task: asyncio.Task | None = None

        # Statistics for monitoring
        self.stats = {
            "total_polls": 0,
            "successful_polls": 0,
            "failed_polls": 0,
            "prompts_generated": 0,
            "last_success_time": 0.0,
            "last_error": None,
        }

        logger.info(
            "PromptManager initialized",
            poll_interval=self.poll_interval,
            lookback_minutes=self.lookback_minutes,
            prompt_max_chars=self.prompt_max_chars,
            api_url=self.bulk_api_url,
        )

    async def start(self):
        """Start the prompt manager background polling."""
        if self.running:
            logger.warning("PromptManager already running")
            return

        self.running = True

        # Create HTTP session with reasonable timeouts
        timeout = aiohttp.ClientTimeout(total=10.0, connect=5.0)
        self.session = aiohttp.ClientSession(timeout=timeout)

        # Start background polling task
        self.poll_task = asyncio.create_task(self._polling_loop())

        logger.info("PromptManager started")

    async def stop(self):
        """Stop the prompt manager and cleanup resources."""
        if not self.running:
            return

        self.running = False

        # Cancel polling task
        if self.poll_task and not self.poll_task.done():
            self.poll_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.poll_task

        # Close HTTP session
        if self.session:
            await self.session.close()
            self.session = None

        logger.info("PromptManager stopped")

    def get_current_prompt(self) -> str:
        """
        Get the current context prompt for transcription.

        Returns:
            str: Current prompt or empty string if expired/unavailable
        """
        # Check if prompt has expired
        if time.time() - self.last_prompt_update > (self.prompt_expiry_minutes * 60) and self.current_prompt:
            logger.debug("Prompt expired, clearing")
            self.current_prompt = ""

        return self.current_prompt

    def get_stats(self) -> dict[str, Any]:
        """Get PromptManager statistics for monitoring."""
        return {
            **self.stats,
            "current_prompt_length": len(self.current_prompt),
            "prompt_age_seconds": time.time() - self.last_prompt_update if self.last_prompt_update > 0 else 0,
            "time_since_last_poll": time.time() - self.last_poll_time if self.last_poll_time > 0 else 0,
            "running": self.running,
        }

    @safe_handler
    async def _polling_loop(self):
        """Background polling loop for chat events."""
        logger.info("Starting chat API polling loop")

        while self.running:
            try:
                # Enforce minimum poll interval
                time_since_last_poll = time.time() - self.last_poll_time
                if time_since_last_poll < self.poll_interval:
                    sleep_time = self.poll_interval - time_since_last_poll
                    await asyncio.sleep(sleep_time)

                # Attempt to fetch and process chat events
                await self._poll_chat_events()

            except asyncio.CancelledError:
                logger.info("Polling loop cancelled")
                break
            except Exception as e:
                logger.error("Unexpected error in polling loop", error=str(e), exc_info=True)
                # Wait before retrying to avoid tight error loops
                await asyncio.sleep(min(30.0, self.poll_interval))

    async def _poll_chat_events(self):
        """Poll Phoenix API for recent chat events and update prompt."""
        if not self.session:
            logger.error("HTTP session not available")
            return

        self.last_poll_time = time.time()
        self.stats["total_polls"] += 1

        try:
            # Calculate hours for lookback (bulk_events endpoint expects hours parameter)
            hours = max(1, self.lookback_minutes // 60)  # Convert minutes to hours, minimum 1 hour

            # API parameters - bulk_events endpoint expects 'hours' not 'since'
            params = {
                "event_type": "channel.chat.message",
                "hours": hours,  # Use hours parameter as expected by the API
            }

            # Make API call directly
            events = await self._fetch_chat_events(params)

            # Process events to extract usernames
            usernames = self._extract_usernames(events)

            # Generate new prompt
            new_prompt = self._generate_prompt(usernames)

            # Update current prompt if changed
            if new_prompt != self.current_prompt:
                self.current_prompt = new_prompt
                self.last_prompt_update = time.time()
                self.stats["prompts_generated"] += 1

                logger.info(
                    "Prompt updated",
                    prompt_length=len(new_prompt),
                    username_count=len(usernames),
                    prompt_preview=new_prompt[:50] + "..." if len(new_prompt) > 50 else new_prompt,
                )
            else:
                logger.debug("No prompt change needed")

            self.stats["successful_polls"] += 1
            self.stats["last_success_time"] = time.time()
            self.stats["last_error"] = None

        except asyncio.CancelledError:
            # Task cancelled during shutdown - this is expected
            logger.debug("Chat events polling cancelled during shutdown")
            raise  # Re-raise to properly handle cancellation

        except (TimeoutError, aiohttp.ClientError) as e:
            # Network/timeout errors - log as warning and continue
            logger.warning("Chat API request failed", error=str(e))
            self.stats["failed_polls"] += 1
            self.stats["last_error"] = str(e)

        except Exception as e:
            # Unexpected error - log and continue
            logger.error("Failed to poll chat events", error=str(e), exc_info=True)
            self.stats["failed_polls"] += 1
            self.stats["last_error"] = str(e)

    async def _fetch_chat_events(self, params: dict[str, Any]) -> list[dict[str, Any]]:
        """
        Fetch chat events from Phoenix API.

        Args:
            params: Query parameters for the API

        Returns:
            list: Chat events from API

        Raises:
            aiohttp.ClientError: On HTTP errors
            asyncio.TimeoutError: On request timeout
            json.JSONDecodeError: On invalid JSON response
        """
        if not self.session:
            raise RuntimeError("HTTP session not available")

        logger.debug("Fetching chat events", params=params)

        async with self.session.get(self.bulk_api_url, params=params) as response:
            # Check for HTTP errors
            if response.status >= 400:
                response_text = await response.text()
                logger.warning(
                    "Chat API HTTP error",
                    status=response.status,
                    response_preview=response_text[:200],
                )
                raise aiohttp.ClientResponseError(
                    request_info=response.request_info,
                    history=response.history,
                    status=response.status,
                    message=f"HTTP {response.status}",
                )

            # Parse JSON response
            try:
                data = await response.json()
            except json.JSONDecodeError as e:
                response_text = await response.text()
                logger.error(
                    "Invalid JSON in chat API response",
                    response_preview=response_text[:200],
                    error=str(e),
                )
                raise

            # Extract events array from Phoenix API response format
            if isinstance(data, dict):
                if "data" in data and isinstance(data["data"], dict) and "events" in data["data"]:
                    # Phoenix API format: {"data": {"events": [...], ...}, "success": true, ...}
                    events = data["data"]["events"]
                elif "events" in data:
                    # Direct events format: {"events": [...]}
                    events = data["events"]
                else:
                    logger.warning("Unexpected API response format", response_keys=list(data.keys()))
                    events = []
            elif isinstance(data, list):
                # Direct list format: [...]
                events = data
            else:
                logger.warning("Unexpected API response format", data_type=type(data).__name__)
                events = []

            logger.debug("Chat events fetched", event_count=len(events))
            return events

    def _extract_usernames(self, events: list[dict[str, Any]]) -> dict[str, int]:
        """
        Extract usernames from chat events with frequency counting.

        Args:
            events: Chat events from API

        Returns:
            dict: Username -> message count mapping
        """
        username_counts = defaultdict(int)
        valid_events = 0

        for event in events:
            try:
                # Extract event data - handle different possible structures
                event_data = event.get("event_data") or event.get("data") or event

                if not isinstance(event_data, dict):
                    continue

                # Extract username from various possible fields
                username = (
                    event_data.get("username")
                    or event_data.get("user_name")
                    or event_data.get("author")
                    or event_data.get("sender")
                )

                if username and isinstance(username, str) and username.strip():
                    # Clean and normalize username
                    clean_username = username.strip()
                    if len(clean_username) <= 50:  # Reasonable username length limit
                        username_counts[clean_username] += 1
                        valid_events += 1

            except Exception as e:
                # Log individual event parsing errors but continue processing
                logger.debug("Error parsing chat event", error=str(e), event_preview=str(event)[:100])
                continue

        logger.debug(
            "Username extraction complete",
            unique_users=len(username_counts),
            valid_events=valid_events,
            total_events=len(events),
        )

        return dict(username_counts)

    def _generate_prompt(self, usernames: dict[str, int]) -> str:
        """
        Generate context prompt from usernames with frequency prioritization.

        Args:
            usernames: Username -> frequency mapping

        Returns:
            str: Generated prompt within character limits
        """
        if not usernames:
            return ""

        # Sort by frequency (most frequent last for emphasis)
        sorted_users = sorted(usernames.items(), key=lambda x: x[1])
        username_list = [user for user, _ in sorted_users]

        # Build prompt iteratively to stay within character limit
        base_text = "Participants include: "

        if len(base_text) >= self.prompt_max_chars:
            logger.warning("Base prompt text too long", base_length=len(base_text))
            return ""

        # Available space for usernames
        available_chars = self.prompt_max_chars - len(base_text) - 1  # -1 for final period

        # Iteratively add usernames until we run out of space
        included_users = []
        current_length = 0

        for username in username_list:
            # Calculate length if we add this username
            separator = ", " if included_users else ""
            addition_length = len(separator) + len(username)

            if current_length + addition_length <= available_chars:
                included_users.append(username)
                current_length += addition_length
            else:
                # No more space
                break

        if not included_users:
            logger.warning("No usernames fit within character limit")
            return ""

        # Construct final prompt
        final_prompt = base_text + ", ".join(included_users) + "."

        logger.debug(
            "Prompt generated",
            total_users=len(username_list),
            included_users=len(included_users),
            prompt_length=len(final_prompt),
            char_limit=self.prompt_max_chars,
        )

        return final_prompt
