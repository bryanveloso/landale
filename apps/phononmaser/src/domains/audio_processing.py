"""
Pure functional domain logic for audio processing.

Contains no side effects - all functions are pure and deterministic.
Handles audio buffer management, chunk processing, and transcription formatting.

Business rules:
- Audio chunks are buffered until they reach a minimum duration
- Buffers are processed when they exceed size or time limits
- Transcription results are formatted consistently for the overlay system
"""

from dataclasses import dataclass
from typing import List, Optional, Tuple
import time


@dataclass
class AudioFormat:
    """Audio format specification."""

    sample_rate: int
    channels: int
    bit_depth: int


@dataclass
class AudioChunk:
    """Individual audio chunk with metadata."""

    timestamp: int  # microseconds
    format: AudioFormat
    data: bytes
    source_id: str


@dataclass
class AudioBuffer:
    """Buffer containing multiple audio chunks."""

    chunks: List[AudioChunk]
    start_timestamp: int
    end_timestamp: int
    total_size: int


@dataclass
class BufferState:
    """Current state of audio buffering."""

    current_buffer: AudioBuffer
    last_flush_time: int  # microseconds
    total_chunks_processed: int


@dataclass
class TranscriptionRequest:
    """Request data for transcription processing."""

    audio_data: bytes
    format: AudioFormat
    start_timestamp: int
    end_timestamp: int
    source_id: str


@dataclass
class TranscriptionResult:
    """Formatted transcription result for overlay system."""

    text: str
    confidence: float
    start_timestamp: int
    end_timestamp: int
    source_id: str
    processing_time_ms: int
    word_count: int


# Buffer Management Domain Logic


def should_flush_buffer(
    buffer_state: BufferState, max_duration_ms: int, max_buffer_size: int, current_time_us: int
) -> bool:
    """
    Determines if the current buffer should be flushed for transcription.

    Pure function with no side effects.

    Args:
        buffer_state: Current buffer state
        max_duration_ms: Maximum buffer duration in milliseconds
        max_buffer_size: Maximum buffer size in bytes
        current_time_us: Current timestamp in microseconds

    Returns:
        True if buffer should be flushed, False otherwise
    """
    if not buffer_state.current_buffer.chunks:
        return False

    # Check size limit
    if buffer_state.current_buffer.total_size >= max_buffer_size:
        return True

    # Check time limit
    buffer_duration_us = current_time_us - buffer_state.current_buffer.start_timestamp
    buffer_duration_ms = buffer_duration_us / 1000

    if buffer_duration_ms >= max_duration_ms:
        return True

    return False


def can_add_chunk_to_buffer(buffer_state: BufferState, chunk: AudioChunk, max_buffer_size: int) -> bool:
    """
    Determines if a new chunk can be added to the current buffer.

    Pure function with no side effects.

    Args:
        buffer_state: Current buffer state
        chunk: Audio chunk to potentially add
        max_buffer_size: Maximum buffer size in bytes

    Returns:
        True if chunk can be added, False otherwise
    """
    if not buffer_state.current_buffer.chunks:
        return True  # Empty buffer can always accept first chunk

    # Check if adding this chunk would exceed size limit
    new_total_size = buffer_state.current_buffer.total_size + len(chunk.data)
    if new_total_size > max_buffer_size:
        return False

    # Check format compatibility
    first_chunk = buffer_state.current_buffer.chunks[0]
    if chunk.format != first_chunk.format:
        return False

    return True


def add_chunk_to_buffer(buffer_state: BufferState, chunk: AudioChunk) -> BufferState:
    """
    Adds a chunk to the current buffer, returning new buffer state.

    Pure function with no side effects.

    Args:
        buffer_state: Current buffer state
        chunk: Audio chunk to add

    Returns:
        New buffer state with chunk added
    """
    current_buffer = buffer_state.current_buffer

    # Calculate new buffer properties
    new_chunks = current_buffer.chunks + [chunk]
    new_total_size = current_buffer.total_size + len(chunk.data)

    # Update timestamps
    start_timestamp = current_buffer.start_timestamp
    if not current_buffer.chunks:  # First chunk
        start_timestamp = chunk.timestamp

    end_timestamp = chunk.timestamp

    new_buffer = AudioBuffer(
        chunks=new_chunks, start_timestamp=start_timestamp, end_timestamp=end_timestamp, total_size=new_total_size
    )

    return BufferState(
        current_buffer=new_buffer,
        last_flush_time=buffer_state.last_flush_time,
        total_chunks_processed=buffer_state.total_chunks_processed,
    )


def create_transcription_request(buffer_state: BufferState) -> Optional[TranscriptionRequest]:
    """
    Creates a transcription request from the current buffer.

    Pure function with no side effects.

    Args:
        buffer_state: Current buffer state

    Returns:
        TranscriptionRequest if buffer has content, None otherwise
    """
    if not buffer_state.current_buffer.chunks:
        return None

    # Merge all chunk data
    merged_data = b"".join(chunk.data for chunk in buffer_state.current_buffer.chunks)

    # Use format from first chunk (all chunks should have same format)
    audio_format = buffer_state.current_buffer.chunks[0].format
    source_id = buffer_state.current_buffer.chunks[0].source_id

    return TranscriptionRequest(
        audio_data=merged_data,
        format=audio_format,
        start_timestamp=buffer_state.current_buffer.start_timestamp,
        end_timestamp=buffer_state.current_buffer.end_timestamp,
        source_id=source_id,
    )


def flush_buffer(buffer_state: BufferState, flush_time_us: int) -> BufferState:
    """
    Flushes the current buffer, returning empty buffer state.

    Pure function with no side effects.

    Args:
        buffer_state: Current buffer state
        flush_time_us: Timestamp when buffer was flushed

    Returns:
        New buffer state with empty buffer
    """
    empty_buffer = AudioBuffer(chunks=[], start_timestamp=0, end_timestamp=0, total_size=0)

    return BufferState(
        current_buffer=empty_buffer,
        last_flush_time=flush_time_us,
        total_chunks_processed=buffer_state.total_chunks_processed + len(buffer_state.current_buffer.chunks),
    )


# Transcription Processing Domain Logic


def calculate_transcription_confidence(raw_confidence: Optional[float]) -> float:
    """
    Normalizes transcription confidence score to 0-1 range.

    Pure function with no side effects.

    Args:
        raw_confidence: Raw confidence score from transcription engine

    Returns:
        Normalized confidence score between 0.0 and 1.0
    """
    if raw_confidence is None:
        return 0.0

    # Clamp to 0-1 range
    return max(0.0, min(1.0, raw_confidence))


def calculate_word_count(text: str) -> int:
    """
    Calculates word count from transcribed text.

    Pure function with no side effects.

    Args:
        text: Transcribed text

    Returns:
        Number of words in the text
    """
    if not text or not text.strip():
        return 0

    # Simple word counting - split on whitespace
    words = text.strip().split()
    return len(words)


def should_emit_transcription(result: TranscriptionResult, min_confidence: float, min_words: int) -> bool:
    """
    Determines if a transcription result should be emitted to the overlay system.

    Pure function with no side effects.

    Args:
        result: Transcription result to evaluate
        min_confidence: Minimum confidence threshold
        min_words: Minimum word count threshold

    Returns:
        True if transcription should be emitted, False otherwise
    """
    if result.confidence < min_confidence:
        return False

    if result.word_count < min_words:
        return False

    if not result.text or not result.text.strip():
        return False

    return True


def format_transcription_result(
    raw_text: str,
    raw_confidence: Optional[float],
    request: TranscriptionRequest,
    processing_start_time_ms: int,
    processing_end_time_ms: int,
) -> TranscriptionResult:
    """
    Formats raw transcription output into standardized result.

    Pure function with no side effects.

    Args:
        raw_text: Raw transcription text
        raw_confidence: Raw confidence score
        request: Original transcription request
        processing_start_time_ms: When processing started (milliseconds)
        processing_end_time_ms: When processing ended (milliseconds)

    Returns:
        Formatted transcription result
    """
    # Clean up text
    cleaned_text = raw_text.strip() if raw_text else ""

    # Calculate metrics
    confidence = calculate_transcription_confidence(raw_confidence)
    word_count = calculate_word_count(cleaned_text)
    processing_time_ms = processing_end_time_ms - processing_start_time_ms

    return TranscriptionResult(
        text=cleaned_text,
        confidence=confidence,
        start_timestamp=request.start_timestamp,
        end_timestamp=request.end_timestamp,
        source_id=request.source_id,
        processing_time_ms=processing_time_ms,
        word_count=word_count,
    )


# Buffer State Initialization


def create_initial_buffer_state() -> BufferState:
    """
    Creates initial empty buffer state.

    Pure function with no side effects.

    Returns:
        Initial buffer state
    """
    empty_buffer = AudioBuffer(chunks=[], start_timestamp=0, end_timestamp=0, total_size=0)

    return BufferState(current_buffer=empty_buffer, last_flush_time=0, total_chunks_processed=0)


# Audio Format Utilities


def formats_are_compatible(format1: AudioFormat, format2: AudioFormat) -> bool:
    """
    Determines if two audio formats are compatible for merging.

    Pure function with no side effects.

    Args:
        format1: First audio format
        format2: Second audio format

    Returns:
        True if formats can be merged, False otherwise
    """
    return (
        format1.sample_rate == format2.sample_rate
        and format1.channels == format2.channels
        and format1.bit_depth == format2.bit_depth
    )


def calculate_buffer_duration_ms(buffer: AudioBuffer, sample_rate: int) -> float:
    """
    Calculates the duration of an audio buffer in milliseconds.

    Pure function with no side effects.

    Args:
        buffer: Audio buffer to measure
        sample_rate: Sample rate in Hz

    Returns:
        Duration in milliseconds
    """
    if not buffer.chunks:
        return 0.0

    duration_us = buffer.end_timestamp - buffer.start_timestamp
    return duration_us / 1000.0
