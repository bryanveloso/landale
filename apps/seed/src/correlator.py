"""Correlates audio transcriptions with chat activity."""

import asyncio
import logging
from collections import Counter, deque
from datetime import datetime, timedelta
from typing import Any

from .context_client import ContextClient
from .events import AnalysisResult, ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent
from .lms_client import LMSClient

logger = logging.getLogger(__name__)


class StreamCorrelator:
    """Correlates transcriptions with chat activity for contextual analysis."""

    def __init__(
        self,
        lms_client: LMSClient,
        context_client: ContextClient | None = None,
        context_window_seconds: int = 120,  # 2 minutes
        analysis_interval_seconds: int = 30,
        correlation_window_seconds: int = 10,  # How far to look for chat reactions
    ):
        self.lms_client = lms_client
        self.context_client = context_client
        self.context_window = context_window_seconds
        self.analysis_interval = analysis_interval_seconds
        self.correlation_window = correlation_window_seconds

        # Buffers for events
        self.transcription_buffer: deque[TranscriptionEvent] = deque()
        self.chat_buffer: deque[ChatMessage] = deque()
        self.emote_buffer: deque[EmoteEvent] = deque()
        self.interaction_buffer: deque[ViewerInteractionEvent] = deque()

        # Analysis state
        self.last_analysis_time = 0
        self.is_analyzing = False

        # Context tracking
        self.context_start_time: datetime | None = None
        self.current_session_id: str | None = None

        # No trigger keywords - patterns emerge naturally through periodic analysis

        # Analysis result callbacks
        self._analysis_callbacks = []

    async def add_transcription(self, event: TranscriptionEvent):
        """Add a transcription event for periodic analysis."""
        # Initialize context window if first transcription
        if not self.context_start_time:
            self.context_start_time = datetime.fromtimestamp(event.timestamp)
            self.current_session_id = self._generate_session_id()

        self.transcription_buffer.append(event)
        self._cleanup_old_events()

        # Check if we should create a context (every 2 minutes)
        await self._check_context_completion()

    async def add_chat_message(self, event: ChatMessage):
        """Add a chat message event."""
        self.chat_buffer.append(event)
        self._cleanup_old_events()

    async def add_emote(self, event: EmoteEvent):
        """Add an emote usage event."""
        self.emote_buffer.append(event)
        self._cleanup_old_events()

    async def add_viewer_interaction(self, event: ViewerInteractionEvent):
        """Add a viewer interaction event as context for periodic analysis."""
        self.interaction_buffer.append(event)
        self._cleanup_old_events()
        logger.debug(f"Community interaction: {event.interaction_type} from {event.username}")

    def on_analysis(self, callback):
        """Register a callback for analysis results."""
        self._analysis_callbacks.append(callback)

    async def analyze(self, immediate: bool = False) -> AnalysisResult | None:
        """Perform correlation analysis."""
        # Skip if already analyzing
        if self.is_analyzing:
            return None

        # Apply cooldown unless immediate
        if not immediate:
            time_since_last = datetime.now().timestamp() - self.last_analysis_time
            if time_since_last < 10:  # 10 second cooldown
                return None

        self.is_analyzing = True
        self.last_analysis_time = datetime.now().timestamp()

        try:
            # Build transcription context
            transcription_context = self._build_transcription_context()
            if not transcription_context:
                return None

            # Build chat context with correlation
            chat_context = self._build_correlated_chat_context()

            # Build viewer interaction context
            interaction_context = self._build_interaction_context()

            # Calculate chat metrics
            chat_velocity = self._calculate_chat_velocity()
            emote_frequency = self._calculate_emote_frequency()
            native_emote_frequency = self._calculate_native_emote_frequency()

            # Combine contexts
            full_context = (
                f"{chat_context} | Interactions: {interaction_context}" if interaction_context else chat_context
            )

            # Send to LMS for analysis
            result = await self.lms_client.analyze(transcription_context, full_context)

            if result:
                # Add correlation metrics
                result.chat_velocity = chat_velocity
                result.emote_frequency = emote_frequency
                result.native_emote_frequency = native_emote_frequency

                logger.info(f"Analysis complete: {result.sentiment} sentiment, {len(result.topics)} topics")

                # Notify all callbacks
                for callback in self._analysis_callbacks:
                    await callback(result)

            return result

        except Exception as e:
            logger.error(f"Analysis failed: {e}")
            return None

        finally:
            self.is_analyzing = False

    async def periodic_analysis_loop(self):
        """Run periodic analysis."""
        while True:
            await asyncio.sleep(self.analysis_interval)
            await self.analyze()

    def _cleanup_old_events(self):
        """Remove events older than context window."""
        cutoff_time = datetime.now().timestamp() - self.context_window

        # Clean transcriptions
        while self.transcription_buffer and self.transcription_buffer[0].timestamp < cutoff_time:
            self.transcription_buffer.popleft()

        # Clean chat
        while self.chat_buffer and self.chat_buffer[0].timestamp < cutoff_time:
            self.chat_buffer.popleft()

        # Clean emotes
        while self.emote_buffer and self.emote_buffer[0].timestamp < cutoff_time:
            self.emote_buffer.popleft()

        # Clean interactions
        while self.interaction_buffer and self.interaction_buffer[0].timestamp < cutoff_time:
            self.interaction_buffer.popleft()

    def _build_transcription_context(self) -> str:
        """Build context string from recent transcriptions."""
        if not self.transcription_buffer:
            return ""

        # Join all recent transcriptions
        texts = [t.text for t in self.transcription_buffer]
        return " ".join(texts)

    def _build_correlated_chat_context(self) -> str:
        """Build chat context that correlates with recent speech."""
        if not self.chat_buffer or not self.transcription_buffer:
            return ""

        context_parts = []

        # For each transcription, find chat messages that came after it
        for transcription in self.transcription_buffer:
            # Find chat messages within correlation window
            correlated_messages = [
                msg
                for msg in self.chat_buffer
                if transcription.timestamp <= msg.timestamp <= transcription.timestamp + self.correlation_window
            ]

            if correlated_messages:
                chat_summary = self._summarize_chat_messages(correlated_messages)
                context_parts.append(f'After "{transcription.text}": {chat_summary}')

        return " | ".join(context_parts) if context_parts else self._summarize_all_recent_chat()

    def _summarize_chat_messages(self, messages: list[ChatMessage]) -> str:
        """Summarize a list of chat messages."""
        if not messages:
            return "no reaction"

        # Count emotes
        emote_counts = Counter()
        for msg in messages:
            for emote in msg.emotes:
                emote_counts[emote] += 1

        # Get sample messages
        sample_texts = [msg.message for msg in messages[:5] if msg.message]

        summary_parts = []

        if emote_counts:
            top_emotes = emote_counts.most_common(3)
            emote_str = ", ".join([f"{emote}x{count}" for emote, count in top_emotes])
            summary_parts.append(f"emotes: {emote_str}")

        if sample_texts:
            sample_str = " / ".join(sample_texts[:3])
            summary_parts.append(f"chat: {sample_str}")

        return f"{len(messages)} messages ({', '.join(summary_parts)})"

    def _summarize_all_recent_chat(self) -> str:
        """Summarize all recent chat when correlation isn't possible."""
        return self._summarize_chat_messages(list(self.chat_buffer))

    def _calculate_chat_velocity(self) -> float:
        """Calculate messages per minute."""
        if not self.chat_buffer:
            return 0.0

        # Get time span of messages
        oldest = self.chat_buffer[0].timestamp
        newest = self.chat_buffer[-1].timestamp
        time_span_minutes = (newest - oldest) / 60

        if time_span_minutes < 0.1:  # Less than 6 seconds
            return 0.0

        return len(self.chat_buffer) / time_span_minutes

    def _calculate_emote_frequency(self) -> dict[str, int]:
        """Calculate emote usage frequency."""
        emote_counts = Counter()

        # Count from chat messages
        for msg in self.chat_buffer:
            for emote in msg.emotes:
                emote_counts[emote] += 1

        # Count from emote events
        for event in self.emote_buffer:
            emote_counts[event.emote_name] += 1

        return dict(emote_counts.most_common(10))  # Top 10 emotes

    def _build_interaction_context(self) -> str:
        """Build context string from recent viewer interactions."""
        if not self.interaction_buffer:
            return ""

        # Group interactions by type
        interaction_counts = Counter()
        recent_interactions = []

        for interaction in self.interaction_buffer:
            interaction_counts[interaction.interaction_type] += 1
            recent_interactions.append(f"{interaction.interaction_type} from {interaction.username}")

        # Build summary
        summary_parts = []

        if interaction_counts:
            counts_str = ", ".join([f"{count} {itype}" for itype, count in interaction_counts.most_common()])
            summary_parts.append(f"Totals: {counts_str}")

        if recent_interactions:
            recent_str = " | ".join(recent_interactions[-5:])  # Last 5 interactions
            summary_parts.append(f"Recent: {recent_str}")

        return " | ".join(summary_parts) if summary_parts else ""

    def _calculate_native_emote_frequency(self) -> dict[str, int]:
        """Calculate native avalon-prefixed emote usage frequency."""
        native_emote_counts = Counter()

        # Count native emotes from chat messages
        for msg in self.chat_buffer:
            for emote in msg.native_emotes:
                native_emote_counts[emote] += 1

        return dict(native_emote_counts.most_common(10))  # Top 10 native emotes

    def _generate_session_id(self) -> str:
        """Generate a session ID in the format stream_YYYY_MM_DD."""
        now = datetime.now()
        return f"stream_{now.year}_{now.month:02d}_{now.day:02d}"

    async def _check_context_completion(self):
        """Check if we should complete the current context window."""
        if not self.context_start_time or not self.transcription_buffer:
            return

        # Check if 2 minutes have passed
        now = datetime.now()
        time_elapsed = (now - self.context_start_time).total_seconds()

        if time_elapsed >= self.context_window:
            await self._create_context()

    async def _create_context(self):
        """Create a memory context from the current window."""
        if not self.transcription_buffer or not self.context_start_time:
            return

        try:
            # Calculate context window end time
            context_end_time = self.context_start_time + timedelta(seconds=self.context_window)

            # Build transcript from all transcriptions in window
            transcript = self._build_transcription_context()
            if not transcript:
                logger.warning("No transcript content for context")
                return

            # Calculate actual duration based on transcriptions
            first_transcription = self.transcription_buffer[0]
            last_transcription = self.transcription_buffer[-1]
            actual_duration = last_transcription.timestamp - first_transcription.timestamp

            # Build maximum data capture
            rich_context_data = await self._build_rich_context_data(
                transcript, actual_duration, first_transcription, last_transcription
            )

            # Build legacy context data for TimescaleDB storage
            context_data = {
                "started": self.context_start_time,
                "ended": context_end_time,
                "session": self.current_session_id,
                "transcript": transcript,
                "duration": actual_duration,
                "chat": rich_context_data.get("community_data", {}).get("chat_summary"),
                "interactions": rich_context_data.get("community_data", {}).get("interactions_summary"),
                "emotes": rich_context_data.get("community_data", {}).get("emotes_summary"),
            }

            # Add AI analysis if available
            ai_analysis = rich_context_data.get("ai_analysis")
            if ai_analysis:
                context_data["patterns"] = ai_analysis.get("patterns")
                context_data["sentiment"] = ai_analysis.get("sentiment")
                context_data["topics"] = ai_analysis.get("topics")

            # Store context in TimescaleDB
            if self.context_client:
                success = await self.context_client.create_context(context_data)
                if success:
                    logger.info(f"Context stored: {self.current_session_id} ({actual_duration:.1f}s)")
                else:
                    logger.error("Failed to store context in TimescaleDB")
            else:
                logger.warning("No context client available, context not stored")

            # Reset for next context window
            self._reset_context_window()

        except Exception as e:
            logger.error(f"Error creating context: {e}")
            self._reset_context_window()

    def _reset_context_window(self):
        """Reset the context window for the next 2-minute period."""
        self.context_start_time = None
        # Keep current_session_id for the same day
        current_date = datetime.now().strftime("%Y_%m_%d")
        if not self.current_session_id or not self.current_session_id.endswith(current_date):
            self.current_session_id = self._generate_session_id()

    def _build_chat_summary(self) -> dict | None:
        """Build chat activity summary for context storage."""
        if not self.chat_buffer:
            return None

        participants = {msg.username for msg in self.chat_buffer}
        message_count = len(self.chat_buffer)
        velocity = self._calculate_chat_velocity()

        return {"message_count": message_count, "velocity": velocity, "participants": list(participants)}

    def _build_interactions_summary(self) -> dict | None:
        """Build viewer interactions summary for context storage."""
        if not self.interaction_buffer:
            return None

        interaction_counts = Counter()
        for interaction in self.interaction_buffer:
            interaction_counts[interaction.interaction_type] += 1

        return dict(interaction_counts)

    def _build_emotes_summary(self) -> dict | None:
        """Build emote usage summary for context storage."""
        emote_frequency = self._calculate_emote_frequency()
        native_emote_frequency = self._calculate_native_emote_frequency()

        if not emote_frequency and not native_emote_frequency:
            return None

        total_emotes = sum(emote_frequency.values()) if emote_frequency else 0
        unique_emotes = len(emote_frequency) if emote_frequency else 0

        return {
            "total_count": total_emotes,
            "unique_emotes": unique_emotes,
            "top_emotes": emote_frequency or {},
            "native_emotes": native_emote_frequency or {},
        }

    async def _build_rich_context_data(
        self, transcript: str, duration: float, _first_transcription, _last_transcription
    ) -> dict:
        """Build comprehensive context data for training and analysis."""
        temporal_data = self._build_temporal_data(duration)
        content_data = self._build_content_data(transcript)
        community_data = self._build_community_data()
        correlation_data = self._build_correlation_data()
        ai_analysis = await self._build_ai_analysis()

        return {
            "temporal_data": temporal_data,
            "content_data": content_data,
            "community_data": community_data,
            "correlation_data": correlation_data,
            "ai_analysis": ai_analysis,
        }

    def _build_temporal_data(self, duration: float) -> dict[str, Any]:
        """Build temporal information for context."""
        return {
            "started": self.context_start_time.isoformat() if self.context_start_time else None,
            "ended": (self.context_start_time + timedelta(seconds=self.context_window)).isoformat()
            if self.context_start_time
            else None,
            "duration": duration,
            "session_id": self.current_session_id,
            "fragment_count": len(self.transcription_buffer),
        }

    def _build_content_data(self, transcript: str) -> dict[str, Any]:
        """Build content analysis data."""
        return {
            "transcript": transcript,
            "transcript_fragments": [
                {"timestamp": t.timestamp, "text": t.text, "duration": t.duration, "confidence": t.confidence}
                for t in self.transcription_buffer
            ],
            "confidence_scores": [t.confidence for t in self.transcription_buffer if t.confidence],
            "speaking_patterns": self._analyze_speaking_patterns(),
            "content_metrics": self._calculate_content_metrics(transcript),
        }

    def _calculate_content_metrics(self, transcript: str) -> dict[str, float]:
        """Calculate content-related metrics."""
        words = transcript.split()
        return {
            "word_count": len(words),
            "sentence_count": transcript.count(".") + transcript.count("!") + transcript.count("?"),
            "avg_words_per_fragment": len(words) / len(self.transcription_buffer) if self.transcription_buffer else 0.0,
        }

    def _build_community_data(self) -> dict[str, Any]:
        """Build community interaction data."""
        return {
            "chat_messages": [self._serialize_chat_message(msg) for msg in self.chat_buffer],
            "emote_events": [self._serialize_emote_event(emote) for emote in self.emote_buffer],
            "viewer_interactions": [
                self._serialize_interaction(interaction) for interaction in self.interaction_buffer
            ],
            "chat_summary": self._build_chat_summary(),
            "interactions_summary": self._build_interactions_summary(),
            "emotes_summary": self._build_emotes_summary(),
            "community_metrics": self._calculate_community_metrics(),
        }

    def _serialize_chat_message(self, msg) -> dict[str, Any]:
        """Serialize a chat message for storage."""
        return {
            "timestamp": msg.timestamp,
            "username": msg.username,
            "message": msg.message,
            "emotes": msg.emotes,
            "native_emotes": msg.native_emotes,
            "is_subscriber": msg.is_subscriber,
            "is_moderator": msg.is_moderator,
        }

    def _serialize_emote_event(self, emote) -> dict[str, Any]:
        """Serialize an emote event for storage."""
        return {
            "timestamp": emote.timestamp,
            "username": emote.username,
            "emote_name": emote.emote_name,
            "emote_id": emote.emote_id,
        }

    def _serialize_interaction(self, interaction) -> dict[str, Any]:
        """Serialize a viewer interaction for storage."""
        return {
            "timestamp": interaction.timestamp,
            "interaction_type": interaction.interaction_type,
            "username": interaction.username,
            "user_id": interaction.user_id,
            "details": interaction.details,
        }

    def _calculate_community_metrics(self) -> dict[str, Any]:
        """Calculate community engagement metrics."""
        return {
            "total_messages": len(self.chat_buffer),
            "unique_participants": len({msg.username for msg in self.chat_buffer}),
            "chat_velocity": self._calculate_chat_velocity(),
            "emote_frequency": self._calculate_emote_frequency(),
            "native_emote_frequency": self._calculate_native_emote_frequency(),
        }

    def _build_correlation_data(self) -> dict[str, Any]:
        """Build correlation analysis data."""
        return {
            "speech_to_chat_correlation": self._analyze_speech_chat_correlation(),
            "temporal_patterns": self._analyze_temporal_patterns(),
            "engagement_patterns": self._analyze_engagement_patterns(),
        }

    async def _build_ai_analysis(self) -> dict[str, Any] | None:
        """Build AI analysis data."""
        analysis_result = await self.analyze(immediate=True)
        if not analysis_result:
            return None

        return {
            "patterns": analysis_result.patterns.dict() if analysis_result.patterns else None,
            "dynamics": analysis_result.dynamics.dict() if analysis_result.dynamics else None,
            "sentiment": analysis_result.sentiment,
            "sentiment_trajectory": analysis_result.sentiment_trajectory,
            "topics": analysis_result.topics,
            "context": analysis_result.context,
            "suggested_actions": analysis_result.suggested_actions,
            "stream_momentum": analysis_result.stream_momentum,
            "model_metadata": {
                "model_used": "current_lms_model",  # TODO: get from config
                "analysis_version": "1.0",
                "timestamp": datetime.now().isoformat(),
            },
        }

    def _analyze_speaking_patterns(self) -> dict:
        """Analyze speaking patterns from transcription data."""
        if not self.transcription_buffer:
            return {}

        fragments = list(self.transcription_buffer)
        if len(fragments) < 2:
            return {}

        # Calculate speaking pace
        total_words = sum(len(t.text.split()) for t in fragments)
        total_duration = fragments[-1].timestamp - fragments[0].timestamp
        words_per_minute = (total_words / total_duration) * 60 if total_duration > 0 else 0.0

        # Calculate pauses between fragments
        pauses = []
        for i in range(1, len(fragments)):
            pause = fragments[i].timestamp - (fragments[i - 1].timestamp + fragments[i - 1].duration)
            pauses.append(max(0, pause))  # Ensure non-negative

        return {
            "words_per_minute": words_per_minute,
            "avg_pause_duration": sum(pauses) / len(pauses) if pauses else 0.0,
            "max_pause_duration": max(pauses) if pauses else 0.0,
            "fragment_durations": [t.duration for t in fragments],
            "avg_fragment_duration": sum(t.duration for t in fragments) / len(fragments) if fragments else 0.0,
        }

    def _analyze_speech_chat_correlation(self) -> dict:
        """Analyze correlation between speech and chat activity."""
        correlations = []

        for transcription in self.transcription_buffer:
            # Find chat messages within correlation window
            correlated_messages = [
                msg
                for msg in self.chat_buffer
                if transcription.timestamp <= msg.timestamp <= transcription.timestamp + self.correlation_window
            ]

            correlations.append(
                {
                    "speech_timestamp": transcription.timestamp,
                    "speech_text": transcription.text,
                    "related_chat_count": len(correlated_messages),
                    "chat_delay_avg": sum(msg.timestamp - transcription.timestamp for msg in correlated_messages)
                    / len(correlated_messages)
                    if correlated_messages
                    else 0.0,
                }
            )

        return {
            "correlations": correlations,
            "avg_chat_response_delay": sum(c["chat_delay_avg"] for c in correlations) / len(correlations)
            if correlations
            else 0.0,
        }

    def _analyze_temporal_patterns(self) -> dict:
        """Analyze how patterns change over time within the context window."""
        if len(self.transcription_buffer) < 3:
            return {}

        # Divide window into segments for trend analysis
        segments = 3
        fragment_count = len(self.transcription_buffer)
        segment_size = fragment_count // segments

        if segment_size == 0:
            return {}

        segment_data = []
        for i in range(segments):
            start_idx = i * segment_size
            end_idx = start_idx + segment_size if i < segments - 1 else fragment_count

            segment_fragments = list(self.transcription_buffer)[start_idx:end_idx]
            segment_chat = [
                msg
                for msg in self.chat_buffer
                if segment_fragments[0].timestamp <= msg.timestamp <= segment_fragments[-1].timestamp
            ]

            segment_data.append(
                {
                    "segment": i + 1,
                    "word_count": sum(len(f.text.split()) for f in segment_fragments),
                    "chat_count": len(segment_chat),
                    "energy_indicator": len(segment_chat) / len(segment_fragments) if segment_fragments else 0.0,
                }
            )

        return {"segments": segment_data, "trend_direction": self._calculate_trend_direction(segment_data)}

    def _analyze_engagement_patterns(self) -> dict:
        """Analyze viewer engagement patterns."""
        return {
            "interaction_types": dict(Counter(interaction.interaction_type for interaction in self.interaction_buffer)),
            "engagement_timeline": [
                {
                    "timestamp": interaction.timestamp,
                    "type": interaction.interaction_type,
                    "username": interaction.username,
                }
                for interaction in self.interaction_buffer
            ],
            "engagement_density": len(self.interaction_buffer) / (self.context_window / 60),  # per minute
        }

    def _calculate_trend_direction(self, segment_data: list[dict]) -> str:
        """Calculate overall trend direction from segment data."""
        if len(segment_data) < 2:
            return "stable"

        energy_trend = [s["energy_indicator"] for s in segment_data]

        if energy_trend[-1] > energy_trend[0] * 1.2:
            return "increasing"
        elif energy_trend[-1] < energy_trend[0] * 0.8:
            return "decreasing"
        else:
            return "stable"
