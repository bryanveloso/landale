"""LM Studio client for AI analysis."""

import asyncio
import json
import random
import time
from collections import deque

import aiohttp
from shared.circuit_breaker import CircuitBreaker

from .events import AnalysisResult, FlexiblePatterns, StreamDynamics
from .logger import get_logger

logger = get_logger(__name__)


class LMSClient:
    """Client for LM Studio API with rate limiting and resilience patterns."""

    def __init__(
        self,
        api_url: str = "http://zelan:1234/v1",
        model: str = "dolphin-2.9.3-llama-3-8b",
        rate_limit: int = 10,
        rate_window: int = 60,
    ):
        self.api_url = api_url
        self.model = model
        self.session: aiohttp.ClientSession | None = None

        # Rate limiting: max requests per time window
        self.rate_limit = rate_limit
        self.rate_window = rate_window  # seconds
        self.rate_limiter = asyncio.Semaphore(rate_limit)
        self.request_times: deque[float] = deque(maxlen=rate_limit)

        # Circuit breaker for external API protection
        self.circuit_breaker = CircuitBreaker(
            name="lms_api", failure_threshold=5, recovery_timeout=120.0, success_threshold=2, logger=logger
        )

    async def __aenter__(self):
        """Async context manager entry."""
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def _check_rate_limit(self):
        """Check and enforce rate limit."""
        now = time.time()
        # Remove old requests outside the window
        while self.request_times and self.request_times[0] < now - self.rate_window:
            self.request_times.popleft()

        # If we're at the limit, wait until we can make another request
        if len(self.request_times) >= self.rate_limit:
            sleep_time = self.rate_window - (now - self.request_times[0]) + 0.1
            logger.warning(f"Rate limit reached, sleeping for {sleep_time:.1f}s")
            await asyncio.sleep(sleep_time)

    async def _analyze_with_backoff(
        self, transcription_context: str, chat_context: str | None = None, max_retries: int = 5, base_delay: float = 0.1
    ) -> AnalysisResult | None:
        """Analyze with exponential backoff on failure."""
        for attempt in range(max_retries):
            try:
                # Use circuit breaker to protect external API calls
                return await self.circuit_breaker.call(self._do_analyze, transcription_context, chat_context)
            except Exception as e:
                if attempt == max_retries - 1:
                    logger.error(f"All {max_retries} attempts failed for LMS analysis")
                    raise

                # Exponential backoff with jitter
                delay = min(base_delay * (2**attempt) + random.uniform(0, 0.1), 5.0)
                logger.warning(f"LMS attempt {attempt + 1}/{max_retries} failed: {e}. Retrying in {delay:.1f}s")
                await asyncio.sleep(delay)

        return None

    async def analyze(self, transcription_context: str, chat_context: str | None = None) -> AnalysisResult | None:
        """Analyze stream context with rate limiting and retry logic."""
        # Check rate limit
        await self._check_rate_limit()

        # Acquire rate limiter semaphore
        async with self.rate_limiter:
            # Track request time
            self.request_times.append(time.time())

            # Analyze with exponential backoff
            return await self._analyze_with_backoff(transcription_context, chat_context)

    async def analyze_with_fallback(
        self, transcription_context: str, chat_context: str | None = None
    ) -> AnalysisResult | None:
        """Analyze with fallback to basic sentiment if LMS fails."""
        try:
            return await self.analyze(transcription_context, chat_context)
        except Exception as e:
            logger.error(f"LMS analysis failed, using fallback: {e}")
            return self._basic_sentiment_analysis(transcription_context, chat_context)

    async def _do_analyze(self, transcription_context: str, chat_context: str | None = None) -> AnalysisResult | None:
        """Perform the actual analysis (internal method)."""
        if not self.session:
            raise RuntimeError("LMSClient must be used as async context manager")

        prompt = self._build_prompt(transcription_context, chat_context)

        try:
            async with self.session.post(
                f"{self.api_url}/chat/completions",
                json={
                    "model": self.model,
                    "messages": [
                        {
                            "role": "system",
                            "content": "You are analyzing a live stream. Provide insights on patterns, dynamics, and sentiment. Always respond with valid JSON.",
                        },
                        {"role": "user", "content": prompt},
                    ],
                    "temperature": 0.7,
                    "max_tokens": 800,
                },
            ) as response:
                if response.status != 200:
                    logger.error(f"LMS API error: {response.status}")
                    return None

                data = await response.json()

                # Validate response structure
                if "choices" not in data or not data["choices"]:
                    logger.error("Invalid LMS response: missing choices")
                    return None

                content = data["choices"][0]["message"]["content"]

                # Parse JSON response with proper error handling
                try:
                    result_data = json.loads(content)
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to parse LMS JSON response: {e}")
                    return None

                # Validate required fields
                required_fields = ["patterns", "sentiment", "context"]
                for field in required_fields:
                    if field not in result_data:
                        logger.error(f"Missing required field in LMS response: {field}")
                        return None

                # Convert to AnalysisResult with error handling
                try:
                    return AnalysisResult(
                        timestamp=int(result_data.get("timestamp", 0)),
                        patterns=FlexiblePatterns(**result_data["patterns"]),
                        dynamics=StreamDynamics(**result_data["dynamics"]) if "dynamics" in result_data else None,
                        sentiment=result_data["sentiment"],
                        sentiment_trajectory=result_data.get("sentimentTrajectory"),
                        topics=result_data.get("topics", []),
                        context=result_data["context"],
                        suggested_actions=result_data.get("suggestedActions", []),
                        stream_momentum=result_data.get("streamMomentum"),
                        transcription_context=transcription_context,
                        chat_context=chat_context,
                    )
                except (KeyError, TypeError, ValueError) as e:
                    logger.error(f"Failed to create AnalysisResult: {e}")
                    return None

        except Exception as e:
            logger.error(f"Failed to analyze with LMS: {e}")
            return None

    def _build_prompt(self, transcription_context: str, chat_context: str | None = None) -> str:
        """Build analysis prompt with available context."""
        base_prompt = f"""You are analyzing a streamer's content to build training data. This represents the last 2 minutes.

Streamer's speech: "{transcription_context}"
"""

        if chat_context:
            base_prompt += f"""
Chat reactions: "{chat_context}"

Analyze BOTH the streamer's words AND how chat is reacting. Consider:
- Is chat responding to what the streamer said?
- What emotions or reactions is chat showing?
- Are there any disconnects between streamer mood and chat mood?
"""

        base_prompt += """
Provide flexible analysis for training data collection:
1. Energy level and engagement depth
2. How content and community are evolving
3. Dynamic topics and mood indicators
4. Overall momentum and flow

Respond with JSON in this exact format:
{
  "timestamp": <current_unix_timestamp>,
  "patterns": {
    "energy_level": 0.0-1.0,
    "engagement_depth": 0.0-1.0,
    "community_sync": 0.0-1.0,
    "content_focus": ["topic1", "topic2"],
    "mood_indicators": {"mood_name": 0.0-1.0},
    "temporal_flow": "description of how things are evolving"
  },
  "dynamics": {
    "energy_trajectory": "ramping_up|winding_down|steady_state|volatile",
    "engagement_trend": "deepening|surfacing|stable|fluctuating",
    "community_trend": "synchronizing|diverging|stable|chaotic",
    "content_evolution": "focused|exploring|transitioning|scattered",
    "overall_momentum": "building|declining|sustained|shifting"
  },
  "sentiment": "positive|negative|neutral|mixed",
  "sentimentTrajectory": "improving|declining|stable|swinging",
  "topics": ["emergent_topic1", "emergent_topic2"],
  "context": "rich description of what's happening and why",
  "suggestedActions": ["action1", "action2"],
  "streamMomentum": {
    "description": "what's driving the current flow",
    "direction": "ramping_up|winding_down|steady_state|chaotic"
  }
}"""

        return base_prompt

    def _basic_sentiment_analysis(self, transcription_context: str, chat_context: str | None = None) -> AnalysisResult:
        """Basic sentiment analysis fallback when LMS is unavailable."""
        logger.warning("Using basic sentiment fallback due to LMS unavailability")

        # Simple word-based sentiment analysis
        positive_words = {"great", "awesome", "good", "nice", "happy", "fun", "love", "excellent", "amazing"}
        negative_words = {"bad", "terrible", "hate", "awful", "sad", "angry", "frustrated", "worst"}

        text_lower = transcription_context.lower()
        words = text_lower.split()

        positive_count = sum(1 for word in words if word in positive_words)
        negative_count = sum(1 for word in words if word in negative_words)

        # Determine sentiment
        if positive_count > negative_count:
            sentiment = "positive"
        elif negative_count > positive_count:
            sentiment = "negative"
        else:
            sentiment = "neutral"

        # Create basic analysis result
        return AnalysisResult(
            timestamp=int(time.time()),
            patterns=FlexiblePatterns(
                energy_level=0.5,
                engagement_depth=0.5,
                community_sync=0.5,
                content_focus=["fallback_analysis"],
                mood_indicators={"uncertain": 1.0},
                temporal_flow="fallback mode - limited analysis",
            ),
            dynamics=StreamDynamics(
                energy_trajectory="steady_state",
                engagement_trend="stable",
                community_trend="stable",
                content_evolution="focused",
                overall_momentum="sustained",
            ),
            sentiment=sentiment,
            sentiment_trajectory="stable",
            topics=["fallback_mode"],
            context="Basic fallback analysis - LMS unavailable",
            suggested_actions=[],
            stream_momentum={"description": "Fallback analysis mode", "direction": "steady_state"},
            transcription_context=transcription_context,
            chat_context=chat_context,
        )

    def get_circuit_stats(self) -> dict:
        """Get circuit breaker statistics."""
        return self.circuit_breaker.get_stats()
