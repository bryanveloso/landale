"""
Pure functional domain logic for correlation analysis.

Contains no side effects - all functions are pure and deterministic.
Handles correlation analysis between transcriptions and chat activity.

Business rules:
- Events are correlated within configurable time windows
- Chat velocity and emote frequency are calculated for context
- Context summaries are built for LMS analysis
- Interaction patterns are analyzed for engagement metrics
"""

from collections import Counter, deque
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional


@dataclass
class TranscriptionEvent:
    """Transcription event with metadata."""

    timestamp: float
    text: str
    duration: float
    confidence: Optional[float] = None


@dataclass
class ChatMessage:
    """Chat message with user and emote data."""

    timestamp: float
    username: str
    message: str
    emotes: List[str]
    native_emotes: List[str]
    is_subscriber: bool = False
    is_moderator: bool = False


@dataclass
class EmoteEvent:
    """Emote usage event."""

    timestamp: float
    username: str
    emote_name: str
    emote_id: str


@dataclass
class ViewerInteractionEvent:
    """Viewer interaction event."""

    timestamp: float
    interaction_type: str
    username: str
    user_id: str
    details: Dict[str, Any]


@dataclass
class CorrelationState:
    """State of correlation buffers and analysis."""

    transcription_buffer: deque[TranscriptionEvent]
    chat_buffer: deque[ChatMessage]
    emote_buffer: deque[EmoteEvent]
    interaction_buffer: deque[ViewerInteractionEvent]
    context_start_time: Optional[datetime]
    current_session_id: Optional[str]
    last_analysis_time: float


@dataclass
class CorrelationMetrics:
    """Metrics calculated from correlation analysis."""

    chat_velocity: float
    emote_frequency: Dict[str, int]
    native_emote_frequency: Dict[str, int]
    total_messages: int
    unique_participants: int


@dataclass
class ContextData:
    """Rich context data for memory storage."""

    temporal_data: Dict[str, Any]
    content_data: Dict[str, Any]
    community_data: Dict[str, Any]
    correlation_data: Dict[str, Any]
    ai_analysis: Optional[Dict[str, Any]]


# Buffer Management Domain Logic


def create_initial_correlation_state(context_window_seconds: int = 120) -> CorrelationState:
    """
    Creates initial empty correlation state.

    Pure function with no side effects.

    Args:
        context_window_seconds: Size of context window in seconds

    Returns:
        Initial correlation state
    """
    return CorrelationState(
        transcription_buffer=deque(),
        chat_buffer=deque(),
        emote_buffer=deque(),
        interaction_buffer=deque(),
        context_start_time=None,
        current_session_id=None,
        last_analysis_time=0.0,
    )


def should_start_context_window(state: CorrelationState, event_timestamp: float) -> bool:
    """
    Determines if a new context window should be started.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        event_timestamp: Timestamp of the triggering event

    Returns:
        True if new context window should start, False otherwise
    """
    return state.context_start_time is None


def should_complete_context_window(
    state: CorrelationState, current_time: datetime, context_window_seconds: int
) -> bool:
    """
    Determines if current context window should be completed.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        current_time: Current datetime
        context_window_seconds: Size of context window in seconds

    Returns:
        True if context should be completed, False otherwise
    """
    if not state.context_start_time or not state.transcription_buffer:
        return False

    time_elapsed = (current_time - state.context_start_time).total_seconds()
    return time_elapsed >= context_window_seconds


def cleanup_old_events(state: CorrelationState, cutoff_time: float) -> CorrelationState:
    """
    Removes events older than cutoff time from all buffers.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        cutoff_time: Timestamp cutoff for event retention

    Returns:
        New correlation state with old events removed
    """
    # Create new buffers with only recent events
    new_transcription_buffer = deque(event for event in state.transcription_buffer if event.timestamp >= cutoff_time)

    new_chat_buffer = deque(event for event in state.chat_buffer if event.timestamp >= cutoff_time)

    new_emote_buffer = deque(event for event in state.emote_buffer if event.timestamp >= cutoff_time)

    new_interaction_buffer = deque(event for event in state.interaction_buffer if event.timestamp >= cutoff_time)

    return CorrelationState(
        transcription_buffer=new_transcription_buffer,
        chat_buffer=new_chat_buffer,
        emote_buffer=new_emote_buffer,
        interaction_buffer=new_interaction_buffer,
        context_start_time=state.context_start_time,
        current_session_id=state.current_session_id,
        last_analysis_time=state.last_analysis_time,
    )


def add_transcription_event(state: CorrelationState, event: TranscriptionEvent) -> CorrelationState:
    """
    Adds transcription event to correlation state.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        event: Transcription event to add

    Returns:
        New correlation state with event added
    """
    new_buffer = state.transcription_buffer.copy()
    new_buffer.append(event)

    # Initialize context if first transcription
    context_start = state.context_start_time
    session_id = state.current_session_id

    if context_start is None:
        context_start = datetime.fromtimestamp(event.timestamp)
        session_id = generate_session_id(context_start)

    return CorrelationState(
        transcription_buffer=new_buffer,
        chat_buffer=state.chat_buffer,
        emote_buffer=state.emote_buffer,
        interaction_buffer=state.interaction_buffer,
        context_start_time=context_start,
        current_session_id=session_id,
        last_analysis_time=state.last_analysis_time,
    )


def add_chat_message(state: CorrelationState, event: ChatMessage) -> CorrelationState:
    """
    Adds chat message to correlation state.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        event: Chat message to add

    Returns:
        New correlation state with event added
    """
    new_buffer = state.chat_buffer.copy()
    new_buffer.append(event)

    return CorrelationState(
        transcription_buffer=state.transcription_buffer,
        chat_buffer=new_buffer,
        emote_buffer=state.emote_buffer,
        interaction_buffer=state.interaction_buffer,
        context_start_time=state.context_start_time,
        current_session_id=state.current_session_id,
        last_analysis_time=state.last_analysis_time,
    )


def add_emote_event(state: CorrelationState, event: EmoteEvent) -> CorrelationState:
    """
    Adds emote event to correlation state.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        event: Emote event to add

    Returns:
        New correlation state with event added
    """
    new_buffer = state.emote_buffer.copy()
    new_buffer.append(event)

    return CorrelationState(
        transcription_buffer=state.transcription_buffer,
        chat_buffer=state.chat_buffer,
        emote_buffer=new_buffer,
        interaction_buffer=state.interaction_buffer,
        context_start_time=state.context_start_time,
        current_session_id=state.current_session_id,
        last_analysis_time=state.last_analysis_time,
    )


def add_interaction_event(state: CorrelationState, event: ViewerInteractionEvent) -> CorrelationState:
    """
    Adds viewer interaction event to correlation state.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        event: Viewer interaction event to add

    Returns:
        New correlation state with event added
    """
    new_buffer = state.interaction_buffer.copy()
    new_buffer.append(event)

    return CorrelationState(
        transcription_buffer=state.transcription_buffer,
        chat_buffer=state.chat_buffer,
        emote_buffer=state.emote_buffer,
        interaction_buffer=new_buffer,
        context_start_time=state.context_start_time,
        current_session_id=state.current_session_id,
        last_analysis_time=state.last_analysis_time,
    )


# Analysis Domain Logic


def should_analyze(state: CorrelationState, current_time: float, cooldown_seconds: int = 10) -> bool:
    """
    Determines if correlation analysis should be performed.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        current_time: Current timestamp
        cooldown_seconds: Minimum time between analyses

    Returns:
        True if analysis should be performed, False otherwise
    """
    time_since_last = current_time - state.last_analysis_time
    return time_since_last >= cooldown_seconds


def build_transcription_context(state: CorrelationState) -> str:
    """
    Builds context string from recent transcriptions.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Combined transcription text
    """
    if not state.transcription_buffer:
        return ""

    texts = [t.text for t in state.transcription_buffer]
    return " ".join(texts)


def build_correlated_chat_context(state: CorrelationState, correlation_window_seconds: int = 10) -> str:
    """
    Builds chat context that correlates with recent speech.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        correlation_window_seconds: Time window for correlation

    Returns:
        Correlated chat context string
    """
    if not state.chat_buffer or not state.transcription_buffer:
        return ""

    context_parts = []

    # For each transcription, find chat messages that came after it
    for transcription in state.transcription_buffer:
        # Find chat messages within correlation window
        correlated_messages = [
            msg
            for msg in state.chat_buffer
            if (transcription.timestamp <= msg.timestamp <= transcription.timestamp + correlation_window_seconds)
        ]

        if correlated_messages:
            chat_summary = summarize_chat_messages(correlated_messages)
            context_parts.append(f'After "{transcription.text}": {chat_summary}')

    return " | ".join(context_parts) if context_parts else summarize_all_recent_chat(state)


def summarize_chat_messages(messages: List[ChatMessage]) -> str:
    """
    Summarizes a list of chat messages.

    Pure function with no side effects.

    Args:
        messages: List of chat messages to summarize

    Returns:
        Summary string
    """
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


def summarize_all_recent_chat(state: CorrelationState) -> str:
    """
    Summarizes all recent chat when correlation isn't possible.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Summary of all recent chat
    """
    return summarize_chat_messages(list(state.chat_buffer))


def calculate_chat_velocity(state: CorrelationState) -> float:
    """
    Calculates messages per minute.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Messages per minute
    """
    if not state.chat_buffer:
        return 0.0

    chat_list = list(state.chat_buffer)
    oldest = chat_list[0].timestamp
    newest = chat_list[-1].timestamp
    time_span_minutes = (newest - oldest) / 60

    if time_span_minutes < 0.1:  # Less than 6 seconds
        return 0.0

    return len(chat_list) / time_span_minutes


def calculate_emote_frequency(state: CorrelationState) -> Dict[str, int]:
    """
    Calculates emote usage frequency.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Dictionary of emote counts
    """
    emote_counts = Counter()

    # Count from chat messages
    for msg in state.chat_buffer:
        for emote in msg.emotes:
            emote_counts[emote] += 1

    # Count from emote events
    for event in state.emote_buffer:
        emote_counts[event.emote_name] += 1

    return dict(emote_counts.most_common(10))


def calculate_native_emote_frequency(state: CorrelationState) -> Dict[str, int]:
    """
    Calculates native avalon-prefixed emote usage frequency.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Dictionary of native emote counts
    """
    native_emote_counts = Counter()

    # Count native emotes from chat messages
    for msg in state.chat_buffer:
        for emote in msg.native_emotes:
            native_emote_counts[emote] += 1

    return dict(native_emote_counts.most_common(10))


def build_interaction_context(state: CorrelationState) -> str:
    """
    Builds context string from recent viewer interactions.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Interaction context string
    """
    if not state.interaction_buffer:
        return ""

    # Group interactions by type
    interaction_counts = Counter()
    recent_interactions = []

    for interaction in state.interaction_buffer:
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


def calculate_correlation_metrics(state: CorrelationState) -> CorrelationMetrics:
    """
    Calculates all correlation metrics from current state.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Correlation metrics
    """
    return CorrelationMetrics(
        chat_velocity=calculate_chat_velocity(state),
        emote_frequency=calculate_emote_frequency(state),
        native_emote_frequency=calculate_native_emote_frequency(state),
        total_messages=len(state.chat_buffer),
        unique_participants=len({msg.username for msg in state.chat_buffer}),
    )


# Context Generation Domain Logic


def generate_session_id(start_time: datetime) -> str:
    """
    Generates a session ID in the format stream_YYYY_MM_DD.

    Pure function with no side effects.

    Args:
        start_time: Start time for the session

    Returns:
        Session ID string
    """
    return f"stream_{start_time.year}_{start_time.month:02d}_{start_time.day:02d}"


def build_temporal_data(state: CorrelationState, duration: float, context_window_seconds: int) -> Dict[str, Any]:
    """
    Builds temporal information for context.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        duration: Actual duration of the context
        context_window_seconds: Size of context window

    Returns:
        Temporal data dictionary
    """
    return {
        "started": state.context_start_time.isoformat() if state.context_start_time else None,
        "ended": (state.context_start_time + timedelta(seconds=context_window_seconds)).isoformat()
        if state.context_start_time
        else None,
        "duration": duration,
        "session_id": state.current_session_id,
        "fragment_count": len(state.transcription_buffer),
    }


def build_content_data(state: CorrelationState, transcript: str) -> Dict[str, Any]:
    """
    Builds content analysis data.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        transcript: Combined transcript text

    Returns:
        Content data dictionary
    """
    return {
        "transcript": transcript,
        "transcript_fragments": [
            {"timestamp": t.timestamp, "text": t.text, "duration": t.duration, "confidence": t.confidence}
            for t in state.transcription_buffer
        ],
        "confidence_scores": [t.confidence for t in state.transcription_buffer if t.confidence],
        "speaking_patterns": analyze_speaking_patterns(state),
        "content_metrics": calculate_content_metrics(transcript, state),
    }


def calculate_content_metrics(transcript: str, state: CorrelationState) -> Dict[str, float]:
    """
    Calculates content-related metrics.

    Pure function with no side effects.

    Args:
        transcript: Combined transcript text
        state: Current correlation state

    Returns:
        Content metrics dictionary
    """
    words = transcript.split()
    sentence_count = transcript.count(".") + transcript.count("!") + transcript.count("?")
    fragment_count = len(state.transcription_buffer)

    return {
        "word_count": len(words),
        "sentence_count": sentence_count,
        "avg_words_per_fragment": len(words) / fragment_count if fragment_count else 0.0,
    }


def analyze_speaking_patterns(state: CorrelationState) -> Dict[str, Any]:
    """
    Analyzes speaking patterns from transcription data.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        Speaking patterns analysis
    """
    if not state.transcription_buffer:
        return {}

    fragments = list(state.transcription_buffer)
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
        "avg_fragment_duration": sum(t.duration for t in fragments) / len(fragments),
    }


def update_analysis_time(state: CorrelationState, analysis_time: float) -> CorrelationState:
    """
    Updates the last analysis time in correlation state.

    Pure function with no side effects.

    Args:
        state: Current correlation state
        analysis_time: Timestamp of analysis

    Returns:
        New correlation state with updated analysis time
    """
    return CorrelationState(
        transcription_buffer=state.transcription_buffer,
        chat_buffer=state.chat_buffer,
        emote_buffer=state.emote_buffer,
        interaction_buffer=state.interaction_buffer,
        context_start_time=state.context_start_time,
        current_session_id=state.current_session_id,
        last_analysis_time=analysis_time,
    )


def reset_context_window(state: CorrelationState) -> CorrelationState:
    """
    Resets the context window for the next period.

    Pure function with no side effects.

    Args:
        state: Current correlation state

    Returns:
        New correlation state with reset context
    """
    # Keep current_session_id for the same day
    current_date = datetime.now().strftime("%Y_%m_%d")
    session_id = state.current_session_id

    if not session_id or not session_id.endswith(current_date):
        session_id = generate_session_id(datetime.now())

    return CorrelationState(
        transcription_buffer=state.transcription_buffer,
        chat_buffer=state.chat_buffer,
        emote_buffer=state.emote_buffer,
        interaction_buffer=state.interaction_buffer,
        context_start_time=None,
        current_session_id=session_id,
        last_analysis_time=state.last_analysis_time,
    )
