"""Correlates audio transcriptions with chat activity."""

import asyncio
import logging
from collections import Counter
from datetime import datetime, timedelta
from typing import Any

from context_client import ContextClient
from domains.correlation_analysis import (
    ChatMessage as DomainChatMessage,
)
from domains.correlation_analysis import (
    EmoteEvent as DomainEmoteEvent,
)
from domains.correlation_analysis import (
    TranscriptionEvent as DomainTranscriptionEvent,
)
from domains.correlation_analysis import (
    ViewerInteractionEvent as DomainViewerInteractionEvent,
)
from domains.correlation_analysis import (
    add_chat_message,
    add_emote_event,
    add_interaction_event,
    add_transcription_event,
    build_content_data,
    build_correlated_chat_context,
    build_interaction_context,
    build_temporal_data,
    build_transcription_context,
    calculate_correlation_metrics,
    cleanup_old_events,
    create_initial_correlation_state,
    reset_context_window,
    should_analyze,
    should_complete_context_window,
    update_analysis_time,
)
from events import AnalysisResult, ChatMessage, EmoteEvent, TranscriptionEvent, ViewerInteractionEvent
from lms_client import LMSClient

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

        # Initialize correlation state using domain
        self.correlation_state = create_initial_correlation_state(context_window_seconds)

        # Analysis state
        self.is_analyzing = False

        # Analysis result callbacks
        self._analysis_callbacks = []

    async def add_transcription(self, event: TranscriptionEvent):
        """Add a transcription event for periodic analysis."""
        # Convert to domain event
        domain_event = DomainTranscriptionEvent(
            timestamp=event.timestamp,
            text=event.text,
            duration=event.duration,
            confidence=getattr(event, "confidence", None),
        )

        # Add to correlation state using domain logic
        self.correlation_state = add_transcription_event(self.correlation_state, domain_event)
        self._cleanup_old_events()

        # Check if we should create a context (every 2 minutes)
        await self._check_context_completion()

    async def add_chat_message(self, event: ChatMessage):
        """Add a chat message event."""
        # Convert to domain event
        domain_event = DomainChatMessage(
            timestamp=event.timestamp,
            username=event.username,
            message=event.message,
            emotes=event.emotes,
            native_emotes=event.native_emotes,
            is_subscriber=event.is_subscriber,
            is_moderator=event.is_moderator,
        )

        # Add to correlation state using domain logic
        self.correlation_state = add_chat_message(self.correlation_state, domain_event)
        self._cleanup_old_events()

    async def add_emote(self, event: EmoteEvent):
        """Add an emote usage event."""
        # Convert to domain event
        domain_event = DomainEmoteEvent(
            timestamp=event.timestamp, username=event.username, emote_name=event.emote_name, emote_id=event.emote_id
        )

        # Add to correlation state using domain logic
        self.correlation_state = add_emote_event(self.correlation_state, domain_event)
        self._cleanup_old_events()

    async def add_viewer_interaction(self, event: ViewerInteractionEvent):
        """Add a viewer interaction event as context for periodic analysis."""
        # Convert to domain event
        domain_event = DomainViewerInteractionEvent(
            timestamp=event.timestamp,
            interaction_type=event.interaction_type,
            username=event.username,
            user_id=event.user_id,
            details=event.details,
        )

        # Add to correlation state using domain logic
        self.correlation_state = add_interaction_event(self.correlation_state, domain_event)
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

        current_time = datetime.now().timestamp()

        # Apply cooldown unless immediate using domain logic
        if not immediate and not should_analyze(self.correlation_state, current_time, 10):
            return None

        self.is_analyzing = True
        self.correlation_state = update_analysis_time(self.correlation_state, current_time)

        try:
            # Build contexts using domain logic
            transcription_context = build_transcription_context(self.correlation_state)
            if not transcription_context:
                return None

            # Build chat context with correlation
            chat_context = build_correlated_chat_context(self.correlation_state, self.correlation_window)

            # Build viewer interaction context
            interaction_context = build_interaction_context(self.correlation_state)

            # Calculate metrics using domain logic
            metrics = calculate_correlation_metrics(self.correlation_state)

            # Combine contexts
            full_context = (
                f"{chat_context} | Interactions: {interaction_context}" if interaction_context else chat_context
            )

            # Send to LMS for analysis
            result = await self.lms_client.analyze(transcription_context, full_context)

            if result:
                # Add correlation metrics from domain
                result.chat_velocity = metrics.chat_velocity
                result.emote_frequency = metrics.emote_frequency
                result.native_emote_frequency = metrics.native_emote_frequency

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

        # Use domain logic for cleanup
        self.correlation_state = cleanup_old_events(self.correlation_state, cutoff_time)

    async def _check_context_completion(self):
        """Check if we should complete the current context window."""
        if should_complete_context_window(self.correlation_state, datetime.now(), self.context_window):
            await self._create_context()

    async def _create_context(self):
        """Create a memory context from the current window."""
        if not self.correlation_state.transcription_buffer or not self.correlation_state.context_start_time:
            return

        try:
            # Calculate context window end time
            context_end_time = self.correlation_state.context_start_time + timedelta(seconds=self.context_window)

            # Build transcript using domain logic
            transcript = build_transcription_context(self.correlation_state)
            if not transcript:
                logger.warning("No transcript content for context")
                return

            # Calculate actual duration based on transcriptions
            transcriptions = list(self.correlation_state.transcription_buffer)
            first_transcription = transcriptions[0]
            last_transcription = transcriptions[-1]
            actual_duration = last_transcription.timestamp - first_transcription.timestamp

            # Build rich context data using domain logic
            rich_context_data = await self._build_rich_context_data(
                transcript, actual_duration, first_transcription, last_transcription
            )

            # Build legacy context data for TimescaleDB storage
            context_data = {
                "started": self.correlation_state.context_start_time,
                "ended": context_end_time,
                "session": self.correlation_state.current_session_id,
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
                    session_id = self.correlation_state.current_session_id
                    logger.info(f"Context stored: {session_id} ({actual_duration:.1f}s)")
                else:
                    logger.error("Failed to store context in TimescaleDB")
            else:
                logger.warning("No context client available, context not stored")

            # Reset for next context window using domain logic
            self.correlation_state = reset_context_window(self.correlation_state)

        except Exception as e:
            logger.error(f"Error creating context: {e}")
            self.correlation_state = reset_context_window(self.correlation_state)

    def _build_chat_summary(self) -> dict | None:
        """Build chat activity summary for context storage."""
        if not self.correlation_state.chat_buffer:
            return None

        participants = {msg.username for msg in self.correlation_state.chat_buffer}
        metrics = calculate_correlation_metrics(self.correlation_state)

        return {
            "message_count": metrics.total_messages,
            "velocity": metrics.chat_velocity,
            "participants": list(participants),
        }

    def _build_interactions_summary(self) -> dict | None:
        """Build viewer interactions summary for context storage."""
        if not self.correlation_state.interaction_buffer:
            return None

        interaction_counts = Counter()
        for interaction in self.correlation_state.interaction_buffer:
            interaction_counts[interaction.interaction_type] += 1

        return dict(interaction_counts)

    def _build_emotes_summary(self) -> dict | None:
        """Build emote usage summary for context storage."""
        metrics = calculate_correlation_metrics(self.correlation_state)

        if not metrics.emote_frequency and not metrics.native_emote_frequency:
            return None

        total_emotes = sum(metrics.emote_frequency.values()) if metrics.emote_frequency else 0
        unique_emotes = len(metrics.emote_frequency) if metrics.emote_frequency else 0

        return {
            "total_count": total_emotes,
            "unique_emotes": unique_emotes,
            "top_emotes": metrics.emote_frequency or {},
            "native_emotes": metrics.native_emote_frequency or {},
        }

    async def _build_rich_context_data(
        self, transcript: str, duration: float, _first_transcription, _last_transcription
    ) -> dict:
        """Build comprehensive context data for training and analysis."""
        # Use domain logic for building context data
        temporal_data = build_temporal_data(self.correlation_state, duration, self.context_window)
        content_data = build_content_data(self.correlation_state, transcript)
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

    def _build_community_data(self) -> dict[str, Any]:
        """Build community interaction data."""
        return {
            "chat_messages": [self._serialize_chat_message(msg) for msg in self.correlation_state.chat_buffer],
            "emote_events": [self._serialize_emote_event(emote) for emote in self.correlation_state.emote_buffer],
            "viewer_interactions": [
                self._serialize_interaction(interaction) for interaction in self.correlation_state.interaction_buffer
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
        metrics = calculate_correlation_metrics(self.correlation_state)
        return {
            "total_messages": metrics.total_messages,
            "unique_participants": metrics.unique_participants,
            "chat_velocity": metrics.chat_velocity,
            "emote_frequency": metrics.emote_frequency,
            "native_emote_frequency": metrics.native_emote_frequency,
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

    def _analyze_speech_chat_correlation(self) -> dict:
        """Analyze correlation between speech and chat activity."""
        correlations = []

        for transcription in self.correlation_state.transcription_buffer:
            # Find chat messages within correlation window
            correlated_messages = [
                msg
                for msg in self.correlation_state.chat_buffer
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
        if len(self.correlation_state.transcription_buffer) < 3:
            return {}

        # Divide window into segments for trend analysis
        segments = 3
        fragment_count = len(self.correlation_state.transcription_buffer)
        segment_size = fragment_count // segments

        if segment_size == 0:
            return {}

        segment_data = []
        for i in range(segments):
            start_idx = i * segment_size
            end_idx = start_idx + segment_size if i < segments - 1 else fragment_count

            segment_fragments = list(self.correlation_state.transcription_buffer)[start_idx:end_idx]
            segment_chat = [
                msg
                for msg in self.correlation_state.chat_buffer
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
            "interaction_types": dict(
                Counter(interaction.interaction_type for interaction in self.correlation_state.interaction_buffer)
            ),
            "engagement_timeline": [
                {
                    "timestamp": interaction.timestamp,
                    "type": interaction.interaction_type,
                    "username": interaction.username,
                }
                for interaction in self.correlation_state.interaction_buffer
            ],
            "engagement_density": len(self.correlation_state.interaction_buffer)
            / (self.context_window / 60),  # per minute
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
