"""
Tests for correlation analysis domain logic.

These tests verify pure functional domain logic without external dependencies.
All functions are tested in isolation with deterministic inputs and outputs.
"""

import sys
from datetime import datetime, timedelta
from pathlib import Path

# Add the src directory to Python path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

from domains.correlation_analysis import (
    ChatMessage,
    EmoteEvent,
    TranscriptionEvent,
    ViewerInteractionEvent,
    add_chat_message,
    add_emote_event,
    add_interaction_event,
    add_transcription_event,
    analyze_speaking_patterns,
    build_content_data,
    build_correlated_chat_context,
    build_interaction_context,
    build_temporal_data,
    build_transcription_context,
    calculate_chat_velocity,
    calculate_content_metrics,
    calculate_correlation_metrics,
    calculate_emote_frequency,
    calculate_native_emote_frequency,
    cleanup_old_events,
    create_initial_correlation_state,
    generate_session_id,
    reset_context_window,
    should_analyze,
    should_complete_context_window,
    should_start_context_window,
    summarize_chat_messages,
    update_analysis_time,
)


class TestCorrelationStateManagement:
    """Tests for correlation state management domain logic."""

    def test_create_initial_correlation_state(self):
        """Initial correlation state should be empty."""
        state = create_initial_correlation_state()

        assert len(state.transcription_buffer) == 0
        assert len(state.chat_buffer) == 0
        assert len(state.emote_buffer) == 0
        assert len(state.interaction_buffer) == 0
        assert state.context_start_time is None
        assert state.current_session_id is None
        assert state.last_analysis_time == 0.0

    def test_should_start_context_window_empty_state(self):
        """Should start context window when no context exists."""
        state = create_initial_correlation_state()
        result = should_start_context_window(state, 1000.0)
        assert result is True

    def test_should_start_context_window_existing_context(self):
        """Should not start context window when context already exists."""
        state = create_initial_correlation_state()
        transcription = TranscriptionEvent(timestamp=1000.0, text="test", duration=1.0)
        state = add_transcription_event(state, transcription)

        result = should_start_context_window(state, 2000.0)
        assert result is False

    def test_should_complete_context_window_no_context(self):
        """Should not complete context window when no context exists."""
        state = create_initial_correlation_state()
        current_time = datetime.now()

        result = should_complete_context_window(state, current_time, 120)
        assert result is False

    def test_should_complete_context_window_time_elapsed(self):
        """Should complete context window when time has elapsed."""
        state = create_initial_correlation_state()
        transcription = TranscriptionEvent(timestamp=1000.0, text="test", duration=1.0)
        state = add_transcription_event(state, transcription)

        # Set current time to 3 minutes after context start
        current_time = state.context_start_time + timedelta(minutes=3)

        result = should_complete_context_window(state, current_time, 120)
        assert result is True

    def test_should_complete_context_window_within_time(self):
        """Should not complete context window when within time limit."""
        state = create_initial_correlation_state()
        transcription = TranscriptionEvent(timestamp=1000.0, text="test", duration=1.0)
        state = add_transcription_event(state, transcription)

        # Set current time to 1 minute after context start
        current_time = state.context_start_time + timedelta(minutes=1)

        result = should_complete_context_window(state, current_time, 120)
        assert result is False

    def test_cleanup_old_events(self):
        """Old events should be removed from all buffers."""
        state = create_initial_correlation_state()

        # Add events with different timestamps
        old_transcription = TranscriptionEvent(timestamp=1000.0, text="old", duration=1.0)
        new_transcription = TranscriptionEvent(timestamp=2000.0, text="new", duration=1.0)

        old_chat = ChatMessage(timestamp=1000.0, username="user1", message="old", emotes=[], native_emotes=[])
        new_chat = ChatMessage(timestamp=2000.0, username="user2", message="new", emotes=[], native_emotes=[])

        old_emote = EmoteEvent(timestamp=1000.0, username="user1", emote_name="old_emote", emote_id="1")
        new_emote = EmoteEvent(timestamp=2000.0, username="user2", emote_name="new_emote", emote_id="2")

        old_interaction = ViewerInteractionEvent(
            timestamp=1000.0, interaction_type="follow", username="user1", user_id="1", details={}
        )
        new_interaction = ViewerInteractionEvent(
            timestamp=2000.0, interaction_type="subscribe", username="user2", user_id="2", details={}
        )

        state = add_transcription_event(state, old_transcription)
        state = add_transcription_event(state, new_transcription)
        state = add_chat_message(state, old_chat)
        state = add_chat_message(state, new_chat)
        state = add_emote_event(state, old_emote)
        state = add_emote_event(state, new_emote)
        state = add_interaction_event(state, old_interaction)
        state = add_interaction_event(state, new_interaction)

        # Cleanup events older than 1500
        cleaned_state = cleanup_old_events(state, 1500.0)

        assert len(cleaned_state.transcription_buffer) == 1
        assert cleaned_state.transcription_buffer[0].text == "new"

        assert len(cleaned_state.chat_buffer) == 1
        assert cleaned_state.chat_buffer[0].message == "new"

        assert len(cleaned_state.emote_buffer) == 1
        assert cleaned_state.emote_buffer[0].emote_name == "new_emote"

        assert len(cleaned_state.interaction_buffer) == 1
        assert cleaned_state.interaction_buffer[0].interaction_type == "subscribe"

    def test_add_transcription_event_first_event(self):
        """First transcription event should initialize context."""
        state = create_initial_correlation_state()
        transcription = TranscriptionEvent(timestamp=1000.0, text="test", duration=1.0)

        new_state = add_transcription_event(state, transcription)

        assert len(new_state.transcription_buffer) == 1
        assert new_state.transcription_buffer[0] == transcription
        assert new_state.context_start_time is not None
        assert new_state.current_session_id is not None

    def test_add_transcription_event_subsequent_event(self):
        """Subsequent transcription events should not change context start."""
        state = create_initial_correlation_state()
        transcription1 = TranscriptionEvent(timestamp=1000.0, text="first", duration=1.0)
        transcription2 = TranscriptionEvent(timestamp=2000.0, text="second", duration=1.0)

        state = add_transcription_event(state, transcription1)
        original_context_start = state.context_start_time

        new_state = add_transcription_event(state, transcription2)

        assert len(new_state.transcription_buffer) == 2
        assert new_state.context_start_time == original_context_start

    def test_add_chat_message(self):
        """Chat messages should be added to buffer."""
        state = create_initial_correlation_state()
        chat = ChatMessage(timestamp=1000.0, username="user", message="hello", emotes=[], native_emotes=[])

        new_state = add_chat_message(state, chat)

        assert len(new_state.chat_buffer) == 1
        assert new_state.chat_buffer[0] == chat

    def test_add_emote_event(self):
        """Emote events should be added to buffer."""
        state = create_initial_correlation_state()
        emote = EmoteEvent(timestamp=1000.0, username="user", emote_name="kappa", emote_id="1")

        new_state = add_emote_event(state, emote)

        assert len(new_state.emote_buffer) == 1
        assert new_state.emote_buffer[0] == emote

    def test_add_interaction_event(self):
        """Interaction events should be added to buffer."""
        state = create_initial_correlation_state()
        interaction = ViewerInteractionEvent(
            timestamp=1000.0, interaction_type="follow", username="user", user_id="123", details={}
        )

        new_state = add_interaction_event(state, interaction)

        assert len(new_state.interaction_buffer) == 1
        assert new_state.interaction_buffer[0] == interaction


class TestAnalysisTriggers:
    """Tests for analysis trigger logic."""

    def test_should_analyze_no_previous_analysis(self):
        """Should analyze when no previous analysis exists."""
        state = create_initial_correlation_state()
        current_time = 1000.0

        result = should_analyze(state, current_time, 10)
        assert result is True

    def test_should_analyze_within_cooldown(self):
        """Should not analyze within cooldown period."""
        state = create_initial_correlation_state()
        state = update_analysis_time(state, 1000.0)
        current_time = 1005.0  # 5 seconds later

        result = should_analyze(state, current_time, 10)
        assert result is False

    def test_should_analyze_after_cooldown(self):
        """Should analyze after cooldown period."""
        state = create_initial_correlation_state()
        state = update_analysis_time(state, 1000.0)
        current_time = 1015.0  # 15 seconds later

        result = should_analyze(state, current_time, 10)
        assert result is True


class TestContextBuilding:
    """Tests for context building domain logic."""

    def test_build_transcription_context_empty(self):
        """Empty transcription buffer should return empty string."""
        state = create_initial_correlation_state()
        result = build_transcription_context(state)
        assert result == ""

    def test_build_transcription_context_with_transcriptions(self):
        """Should combine all transcription texts."""
        state = create_initial_correlation_state()
        t1 = TranscriptionEvent(timestamp=1000.0, text="hello", duration=1.0)
        t2 = TranscriptionEvent(timestamp=2000.0, text="world", duration=1.0)

        state = add_transcription_event(state, t1)
        state = add_transcription_event(state, t2)

        result = build_transcription_context(state)
        assert result == "hello world"

    def test_build_correlated_chat_context_empty_buffers(self):
        """Empty buffers should return empty string."""
        state = create_initial_correlation_state()
        result = build_correlated_chat_context(state, 10)
        assert result == ""

    def test_build_correlated_chat_context_with_correlation(self):
        """Should correlate chat messages with transcriptions."""
        state = create_initial_correlation_state()

        # Add transcription
        transcription = TranscriptionEvent(timestamp=1000.0, text="hello", duration=1.0)
        state = add_transcription_event(state, transcription)

        # Add correlated chat message
        chat = ChatMessage(timestamp=1005.0, username="user", message="hi there", emotes=["kappa"], native_emotes=[])
        state = add_chat_message(state, chat)

        result = build_correlated_chat_context(state, 10)
        assert 'After "hello":' in result
        assert "1 messages" in result
        assert "emotes: kappax1" in result

    def test_summarize_chat_messages_empty(self):
        """Empty message list should return 'no reaction'."""
        result = summarize_chat_messages([])
        assert result == "no reaction"

    def test_summarize_chat_messages_with_emotes_and_text(self):
        """Should summarize messages with emotes and text."""
        messages = [
            ChatMessage(
                timestamp=1000.0, username="user1", message="great stream", emotes=["kappa", "kappa"], native_emotes=[]
            ),
            ChatMessage(timestamp=1001.0, username="user2", message="awesome", emotes=["poggers"], native_emotes=[]),
        ]

        result = summarize_chat_messages(messages)
        assert "2 messages" in result
        assert "emotes: kappax2, poggersx1" in result
        assert "chat: great stream / awesome" in result

    def test_build_interaction_context_empty(self):
        """Empty interaction buffer should return empty string."""
        state = create_initial_correlation_state()
        result = build_interaction_context(state)
        assert result == ""

    def test_build_interaction_context_with_interactions(self):
        """Should build interaction summary."""
        state = create_initial_correlation_state()

        i1 = ViewerInteractionEvent(
            timestamp=1000.0, interaction_type="follow", username="user1", user_id="1", details={}
        )
        i2 = ViewerInteractionEvent(
            timestamp=1001.0, interaction_type="follow", username="user2", user_id="2", details={}
        )
        i3 = ViewerInteractionEvent(
            timestamp=1002.0, interaction_type="subscribe", username="user3", user_id="3", details={}
        )

        state = add_interaction_event(state, i1)
        state = add_interaction_event(state, i2)
        state = add_interaction_event(state, i3)

        result = build_interaction_context(state)
        assert "Totals: 2 follow, 1 subscribe" in result
        assert "Recent:" in result


class TestMetricsCalculation:
    """Tests for metrics calculation domain logic."""

    def test_calculate_chat_velocity_empty(self):
        """Empty chat buffer should return 0 velocity."""
        state = create_initial_correlation_state()
        result = calculate_chat_velocity(state)
        assert result == 0.0

    def test_calculate_chat_velocity_single_message(self):
        """Single message should return 0 velocity."""
        state = create_initial_correlation_state()
        chat = ChatMessage(timestamp=1000.0, username="user", message="hello", emotes=[], native_emotes=[])
        state = add_chat_message(state, chat)

        result = calculate_chat_velocity(state)
        assert result == 0.0

    def test_calculate_chat_velocity_multiple_messages(self):
        """Multiple messages should calculate velocity correctly."""
        state = create_initial_correlation_state()

        # Add messages 1 minute apart (should be 2 messages per minute)
        chat1 = ChatMessage(timestamp=1000.0, username="user1", message="hello", emotes=[], native_emotes=[])
        chat2 = ChatMessage(timestamp=1060.0, username="user2", message="world", emotes=[], native_emotes=[])

        state = add_chat_message(state, chat1)
        state = add_chat_message(state, chat2)

        result = calculate_chat_velocity(state)
        assert result == 2.0  # 2 messages per minute

    def test_calculate_emote_frequency_empty(self):
        """Empty buffers should return empty frequency."""
        state = create_initial_correlation_state()
        result = calculate_emote_frequency(state)
        assert result == {}

    def test_calculate_emote_frequency_with_emotes(self):
        """Should count emotes from both chat and emote events."""
        state = create_initial_correlation_state()

        # Add chat message with emotes
        chat = ChatMessage(
            timestamp=1000.0, username="user1", message="test", emotes=["kappa", "kappa", "poggers"], native_emotes=[]
        )
        state = add_chat_message(state, chat)

        # Add emote event
        emote = EmoteEvent(timestamp=1001.0, username="user2", emote_name="kappa", emote_id="1")
        state = add_emote_event(state, emote)

        result = calculate_emote_frequency(state)
        assert result["kappa"] == 3  # 2 from chat + 1 from event
        assert result["poggers"] == 1

    def test_calculate_native_emote_frequency(self):
        """Should count only native emotes."""
        state = create_initial_correlation_state()

        chat = ChatMessage(
            timestamp=1000.0,
            username="user",
            message="test",
            emotes=["kappa"],
            native_emotes=["avalon_smile", "avalon_smile"],
        )
        state = add_chat_message(state, chat)

        result = calculate_native_emote_frequency(state)
        assert result["avalon_smile"] == 2
        assert "kappa" not in result

    def test_calculate_correlation_metrics(self):
        """Should calculate all metrics correctly."""
        state = create_initial_correlation_state()

        # Add chat messages
        chat1 = ChatMessage(timestamp=1000.0, username="user1", message="hello", emotes=["kappa"], native_emotes=[])
        chat2 = ChatMessage(timestamp=1060.0, username="user2", message="world", emotes=["poggers"], native_emotes=[])

        state = add_chat_message(state, chat1)
        state = add_chat_message(state, chat2)

        metrics = calculate_correlation_metrics(state)

        assert metrics.chat_velocity == 2.0
        assert metrics.emote_frequency["kappa"] == 1
        assert metrics.emote_frequency["poggers"] == 1
        assert metrics.total_messages == 2
        assert metrics.unique_participants == 2


class TestContentAnalysis:
    """Tests for content analysis domain logic."""

    def test_generate_session_id(self):
        """Should generate session ID in correct format."""
        start_time = datetime(2024, 3, 15, 14, 30, 0)
        result = generate_session_id(start_time)
        assert result == "stream_2024_03_15"

    def test_calculate_content_metrics(self):
        """Should calculate content metrics correctly."""
        state = create_initial_correlation_state()
        t1 = TranscriptionEvent(timestamp=1000.0, text="hello world", duration=1.0)
        t2 = TranscriptionEvent(timestamp=2000.0, text="how are you?", duration=1.0)

        state = add_transcription_event(state, t1)
        state = add_transcription_event(state, t2)

        transcript = "hello world how are you?"
        metrics = calculate_content_metrics(transcript, state)

        assert metrics["word_count"] == 5
        assert metrics["sentence_count"] == 1  # One question mark
        assert metrics["avg_words_per_fragment"] == 2.5  # 5 words / 2 fragments

    def test_analyze_speaking_patterns_empty(self):
        """Empty transcription buffer should return empty patterns."""
        state = create_initial_correlation_state()
        result = analyze_speaking_patterns(state)
        assert result == {}

    def test_analyze_speaking_patterns_insufficient_data(self):
        """Single transcription should return empty patterns."""
        state = create_initial_correlation_state()
        t1 = TranscriptionEvent(timestamp=1000.0, text="hello", duration=1.0)
        state = add_transcription_event(state, t1)

        result = analyze_speaking_patterns(state)
        assert result == {}

    def test_analyze_speaking_patterns_with_data(self):
        """Should analyze speaking patterns correctly."""
        state = create_initial_correlation_state()

        # Add transcriptions with pauses
        t1 = TranscriptionEvent(timestamp=1000.0, text="hello world", duration=2.0)  # 2 words in 2 seconds
        t2 = TranscriptionEvent(timestamp=1005.0, text="how are you", duration=3.0)  # 3 words in 3 seconds, 3s pause

        state = add_transcription_event(state, t1)
        state = add_transcription_event(state, t2)

        result = analyze_speaking_patterns(state)

        assert result["words_per_minute"] == 60.0  # 5 words in 5 seconds = 60 wpm
        assert result["avg_pause_duration"] == 3.0  # One pause of 3 seconds
        assert result["max_pause_duration"] == 3.0
        assert result["avg_fragment_duration"] == 2.5  # (2 + 3) / 2

    def test_build_temporal_data(self):
        """Should build temporal data correctly."""
        state = create_initial_correlation_state()
        transcription = TranscriptionEvent(timestamp=1000.0, text="test", duration=1.0)
        state = add_transcription_event(state, transcription)

        result = build_temporal_data(state, 120.0, 120)

        assert result["session_id"] == state.current_session_id
        assert result["duration"] == 120.0
        assert result["fragment_count"] == 1
        assert "started" in result
        assert "ended" in result

    def test_build_content_data(self):
        """Should build comprehensive content data."""
        state = create_initial_correlation_state()

        t1 = TranscriptionEvent(timestamp=1000.0, text="hello", duration=1.0, confidence=0.9)
        t2 = TranscriptionEvent(timestamp=2000.0, text="world", duration=1.0, confidence=0.8)

        state = add_transcription_event(state, t1)
        state = add_transcription_event(state, t2)

        transcript = "hello world"
        result = build_content_data(state, transcript)

        assert result["transcript"] == transcript
        assert len(result["transcript_fragments"]) == 2
        assert result["confidence_scores"] == [0.9, 0.8]
        assert "speaking_patterns" in result
        assert "content_metrics" in result


class TestStateUpdates:
    """Tests for state update operations."""

    def test_update_analysis_time(self):
        """Should update last analysis time."""
        state = create_initial_correlation_state()
        new_time = 1000.0

        updated_state = update_analysis_time(state, new_time)

        assert updated_state.last_analysis_time == new_time
        # Other fields should remain unchanged
        assert updated_state.transcription_buffer == state.transcription_buffer
        assert updated_state.context_start_time == state.context_start_time

    def test_reset_context_window(self):
        """Should reset context window while preserving session for same day."""
        state = create_initial_correlation_state()
        transcription = TranscriptionEvent(timestamp=1000.0, text="test", duration=1.0)
        state = add_transcription_event(state, transcription)

        original_session_id = state.current_session_id

        reset_state = reset_context_window(state)

        assert reset_state.context_start_time is None
        # Session ID should be preserved if same day
        current_date = datetime.now().strftime("%Y_%m_%d")
        if original_session_id and original_session_id.endswith(current_date):
            assert reset_state.current_session_id == original_session_id
        else:
            assert reset_state.current_session_id is not None
            assert reset_state.current_session_id.startswith("stream_")
