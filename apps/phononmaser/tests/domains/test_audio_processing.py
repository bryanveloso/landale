"""
Tests for audio processing domain logic.

These tests verify pure functional domain logic without external dependencies.
All functions are tested in isolation with deterministic inputs and outputs.
"""

import sys
from pathlib import Path

# Add the src directory to Python path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "src"))

import pytest
from domains.audio_processing import (
    AudioFormat,
    AudioChunk,
    AudioBuffer,
    BufferState,
    TranscriptionRequest,
    TranscriptionResult,
    should_flush_buffer,
    can_add_chunk_to_buffer,
    add_chunk_to_buffer,
    create_transcription_request,
    flush_buffer,
    calculate_transcription_confidence,
    calculate_word_count,
    should_emit_transcription,
    format_transcription_result,
    create_initial_buffer_state,
    formats_are_compatible,
    calculate_buffer_duration_ms,
)


class TestBufferManagement:
    """Tests for audio buffer management domain logic."""

    def test_should_flush_buffer_empty_buffer(self):
        """Empty buffer should not be flushed."""
        buffer_state = create_initial_buffer_state()
        result = should_flush_buffer(buffer_state, 1000, 1024, 1000000)
        assert result is False

    def test_should_flush_buffer_size_limit(self):
        """Buffer should be flushed when size limit is exceeded."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunk = AudioChunk(timestamp=1000, format=format, data=b"x" * 2000, source_id="test")

        buffer = AudioBuffer(chunks=[chunk], start_timestamp=1000, end_timestamp=1000, total_size=2000)
        buffer_state = BufferState(current_buffer=buffer, last_flush_time=0, total_chunks_processed=0)

        result = should_flush_buffer(buffer_state, 10000, 1000, 2000)
        assert result is True

    def test_should_flush_buffer_time_limit(self):
        """Buffer should be flushed when time limit is exceeded."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunk = AudioChunk(timestamp=1000000, format=format, data=b"x" * 100, source_id="test")

        buffer = AudioBuffer(chunks=[chunk], start_timestamp=1000000, end_timestamp=1000000, total_size=100)
        buffer_state = BufferState(current_buffer=buffer, last_flush_time=0, total_chunks_processed=0)

        # Current time is 2 seconds later (2000000 us)
        current_time = 1000000 + (2000 * 1000)  # 2000ms later
        result = should_flush_buffer(buffer_state, 1500, 10000, current_time)
        assert result is True

    def test_should_flush_buffer_within_limits(self):
        """Buffer should not be flushed when within limits."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunk = AudioChunk(timestamp=1000000, format=format, data=b"x" * 100, source_id="test")

        buffer = AudioBuffer(chunks=[chunk], start_timestamp=1000000, end_timestamp=1000000, total_size=100)
        buffer_state = BufferState(current_buffer=buffer, last_flush_time=0, total_chunks_processed=0)

        # Current time is 1 second later (within 1500ms limit)
        current_time = 1000000 + (1000 * 1000)  # 1000ms later
        result = should_flush_buffer(buffer_state, 1500, 10000, current_time)
        assert result is False

    def test_can_add_chunk_to_empty_buffer(self):
        """First chunk can always be added to empty buffer."""
        buffer_state = create_initial_buffer_state()
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunk = AudioChunk(timestamp=1000, format=format, data=b"test", source_id="test")

        result = can_add_chunk_to_buffer(buffer_state, chunk, 1000)
        assert result is True

    def test_can_add_chunk_size_limit(self):
        """Chunk should not be added if it exceeds size limit."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        existing_chunk = AudioChunk(timestamp=1000, format=format, data=b"x" * 500, source_id="test")

        buffer = AudioBuffer(chunks=[existing_chunk], start_timestamp=1000, end_timestamp=1000, total_size=500)
        buffer_state = BufferState(current_buffer=buffer, last_flush_time=0, total_chunks_processed=0)

        new_chunk = AudioChunk(timestamp=2000, format=format, data=b"x" * 600, source_id="test")
        result = can_add_chunk_to_buffer(buffer_state, new_chunk, 1000)
        assert result is False

    def test_can_add_chunk_format_mismatch(self):
        """Chunk should not be added if format doesn't match."""
        format1 = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        format2 = AudioFormat(sample_rate=44100, channels=2, bit_depth=16)

        existing_chunk = AudioChunk(timestamp=1000, format=format1, data=b"test", source_id="test")

        buffer = AudioBuffer(chunks=[existing_chunk], start_timestamp=1000, end_timestamp=1000, total_size=4)
        buffer_state = BufferState(current_buffer=buffer, last_flush_time=0, total_chunks_processed=0)

        new_chunk = AudioChunk(timestamp=2000, format=format2, data=b"test", source_id="test")
        result = can_add_chunk_to_buffer(buffer_state, new_chunk, 1000)
        assert result is False

    def test_add_chunk_to_buffer(self):
        """Adding chunk should update buffer state correctly."""
        buffer_state = create_initial_buffer_state()
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunk = AudioChunk(timestamp=1000, format=format, data=b"test", source_id="test")

        new_state = add_chunk_to_buffer(buffer_state, chunk)

        assert len(new_state.current_buffer.chunks) == 1
        assert new_state.current_buffer.chunks[0] == chunk
        assert new_state.current_buffer.total_size == 4
        assert new_state.current_buffer.start_timestamp == 1000
        assert new_state.current_buffer.end_timestamp == 1000
        assert new_state.total_chunks_processed == 0

    def test_add_multiple_chunks_to_buffer(self):
        """Adding multiple chunks should update timestamps and size correctly."""
        buffer_state = create_initial_buffer_state()
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk1 = AudioChunk(timestamp=1000, format=format, data=b"aaaa", source_id="test")
        chunk2 = AudioChunk(timestamp=2000, format=format, data=b"bbbb", source_id="test")

        state1 = add_chunk_to_buffer(buffer_state, chunk1)
        state2 = add_chunk_to_buffer(state1, chunk2)

        assert len(state2.current_buffer.chunks) == 2
        assert state2.current_buffer.total_size == 8
        assert state2.current_buffer.start_timestamp == 1000
        assert state2.current_buffer.end_timestamp == 2000

    def test_create_transcription_request_empty_buffer(self):
        """Empty buffer should return None for transcription request."""
        buffer_state = create_initial_buffer_state()
        result = create_transcription_request(buffer_state)
        assert result is None

    def test_create_transcription_request_with_chunks(self):
        """Buffer with chunks should create valid transcription request."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunk1 = AudioChunk(timestamp=1000, format=format, data=b"aaaa", source_id="test")
        chunk2 = AudioChunk(timestamp=2000, format=format, data=b"bbbb", source_id="test")

        buffer = AudioBuffer(chunks=[chunk1, chunk2], start_timestamp=1000, end_timestamp=2000, total_size=8)
        buffer_state = BufferState(current_buffer=buffer, last_flush_time=0, total_chunks_processed=0)

        request = create_transcription_request(buffer_state)

        assert request is not None
        assert request.audio_data == b"aaaabbbb"
        assert request.format == format
        assert request.start_timestamp == 1000
        assert request.end_timestamp == 2000
        assert request.source_id == "test"

    def test_flush_buffer(self):
        """Flushing buffer should reset to empty state and update counters."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunk = AudioChunk(timestamp=1000, format=format, data=b"test", source_id="test")

        buffer = AudioBuffer(chunks=[chunk], start_timestamp=1000, end_timestamp=1000, total_size=4)
        buffer_state = BufferState(current_buffer=buffer, last_flush_time=0, total_chunks_processed=5)

        new_state = flush_buffer(buffer_state, 5000)

        assert len(new_state.current_buffer.chunks) == 0
        assert new_state.current_buffer.total_size == 0
        assert new_state.last_flush_time == 5000
        assert new_state.total_chunks_processed == 6  # 5 + 1 chunk from buffer


class TestTranscriptionProcessing:
    """Tests for transcription processing domain logic."""

    def test_calculate_transcription_confidence_none(self):
        """None confidence should return 0.0."""
        result = calculate_transcription_confidence(None)
        assert result == 0.0

    def test_calculate_transcription_confidence_valid(self):
        """Valid confidence should be returned as-is."""
        result = calculate_transcription_confidence(0.85)
        assert result == 0.85

    def test_calculate_transcription_confidence_clamp_high(self):
        """Confidence > 1.0 should be clamped to 1.0."""
        result = calculate_transcription_confidence(1.5)
        assert result == 1.0

    def test_calculate_transcription_confidence_clamp_low(self):
        """Confidence < 0.0 should be clamped to 0.0."""
        result = calculate_transcription_confidence(-0.5)
        assert result == 0.0

    def test_calculate_word_count_empty(self):
        """Empty text should return 0 words."""
        assert calculate_word_count("") == 0
        assert calculate_word_count("   ") == 0
        assert calculate_word_count(None) == 0

    def test_calculate_word_count_single_word(self):
        """Single word should return 1."""
        result = calculate_word_count("hello")
        assert result == 1

    def test_calculate_word_count_multiple_words(self):
        """Multiple words should be counted correctly."""
        result = calculate_word_count("hello world test")
        assert result == 3

    def test_calculate_word_count_extra_spaces(self):
        """Extra spaces should be handled correctly."""
        result = calculate_word_count("  hello   world  ")
        assert result == 2

    def test_should_emit_transcription_low_confidence(self):
        """Low confidence transcription should not be emitted."""
        result = TranscriptionResult(
            text="hello world",
            confidence=0.3,
            start_timestamp=1000,
            end_timestamp=2000,
            source_id="test",
            processing_time_ms=100,
            word_count=2,
        )

        should_emit = should_emit_transcription(result, min_confidence=0.5, min_words=1)
        assert should_emit is False

    def test_should_emit_transcription_few_words(self):
        """Transcription with too few words should not be emitted."""
        result = TranscriptionResult(
            text="hello",
            confidence=0.8,
            start_timestamp=1000,
            end_timestamp=2000,
            source_id="test",
            processing_time_ms=100,
            word_count=1,
        )

        should_emit = should_emit_transcription(result, min_confidence=0.5, min_words=2)
        assert should_emit is False

    def test_should_emit_transcription_empty_text(self):
        """Empty text should not be emitted."""
        result = TranscriptionResult(
            text="",
            confidence=0.8,
            start_timestamp=1000,
            end_timestamp=2000,
            source_id="test",
            processing_time_ms=100,
            word_count=0,
        )

        should_emit = should_emit_transcription(result, min_confidence=0.5, min_words=1)
        assert should_emit is False

    def test_should_emit_transcription_valid(self):
        """Valid transcription should be emitted."""
        result = TranscriptionResult(
            text="hello world",
            confidence=0.8,
            start_timestamp=1000,
            end_timestamp=2000,
            source_id="test",
            processing_time_ms=100,
            word_count=2,
        )

        should_emit = should_emit_transcription(result, min_confidence=0.5, min_words=1)
        assert should_emit is True

    def test_format_transcription_result(self):
        """Transcription result should be formatted correctly."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        request = TranscriptionRequest(
            audio_data=b"test", format=format, start_timestamp=1000, end_timestamp=2000, source_id="test"
        )

        result = format_transcription_result(
            raw_text="  Hello World  ",
            raw_confidence=0.85,
            request=request,
            processing_start_time_ms=100,
            processing_end_time_ms=250,
        )

        assert result.text == "Hello World"
        assert result.confidence == 0.85
        assert result.start_timestamp == 1000
        assert result.end_timestamp == 2000
        assert result.source_id == "test"
        assert result.processing_time_ms == 150
        assert result.word_count == 2

    def test_format_transcription_result_none_confidence(self):
        """None confidence should be handled in formatting."""
        format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        request = TranscriptionRequest(
            audio_data=b"test", format=format, start_timestamp=1000, end_timestamp=2000, source_id="test"
        )

        result = format_transcription_result(
            raw_text="hello",
            raw_confidence=None,
            request=request,
            processing_start_time_ms=100,
            processing_end_time_ms=200,
        )

        assert result.confidence == 0.0


class TestAudioFormatUtilities:
    """Tests for audio format utility functions."""

    def test_formats_are_compatible_identical(self):
        """Identical formats should be compatible."""
        format1 = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        format2 = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        result = formats_are_compatible(format1, format2)
        assert result is True

    def test_formats_are_compatible_different_sample_rate(self):
        """Different sample rates should not be compatible."""
        format1 = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        format2 = AudioFormat(sample_rate=44100, channels=1, bit_depth=16)

        result = formats_are_compatible(format1, format2)
        assert result is False

    def test_formats_are_compatible_different_channels(self):
        """Different channel counts should not be compatible."""
        format1 = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        format2 = AudioFormat(sample_rate=16000, channels=2, bit_depth=16)

        result = formats_are_compatible(format1, format2)
        assert result is False

    def test_formats_are_compatible_different_bit_depth(self):
        """Different bit depths should not be compatible."""
        format1 = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        format2 = AudioFormat(sample_rate=16000, channels=1, bit_depth=24)

        result = formats_are_compatible(format1, format2)
        assert result is False

    def test_calculate_buffer_duration_ms_empty(self):
        """Empty buffer should have 0 duration."""
        buffer = AudioBuffer(chunks=[], start_timestamp=0, end_timestamp=0, total_size=0)

        duration = calculate_buffer_duration_ms(buffer, 16000)
        assert duration == 0.0

    def test_calculate_buffer_duration_ms_with_chunks(self):
        """Buffer duration should be calculated correctly."""
        buffer = AudioBuffer(
            chunks=[],  # chunks don't matter for duration calculation
            start_timestamp=1000000,  # 1 second in microseconds
            end_timestamp=2500000,  # 2.5 seconds in microseconds
            total_size=100,
        )

        duration = calculate_buffer_duration_ms(buffer, 16000)
        assert duration == 1500.0  # 1.5 seconds = 1500ms


class TestBufferStateInitialization:
    """Tests for buffer state initialization."""

    def test_create_initial_buffer_state(self):
        """Initial buffer state should be empty."""
        state = create_initial_buffer_state()

        assert len(state.current_buffer.chunks) == 0
        assert state.current_buffer.total_size == 0
        assert state.current_buffer.start_timestamp == 0
        assert state.current_buffer.end_timestamp == 0
        assert state.last_flush_time == 0
        assert state.total_chunks_processed == 0
