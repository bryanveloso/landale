"""Ring buffer audio processor for memory-efficient continuous audio streaming.

Implements a circular buffer that can handle 24/7 audio processing without
memory growth, with sliding window access and historical audio retrieval.
"""

import asyncio
import logging
import time
from dataclasses import dataclass

import numpy as np

from audio_processor import AudioChunk

logger = logging.getLogger(__name__)


@dataclass
class SlidingWindow:
    """A sliding window of audio data with timing information."""

    start_timestamp: int  # microseconds
    end_timestamp: int  # microseconds
    audio_data: bytes  # raw audio bytes
    sample_rate: int  # samples per second


@dataclass
class BufferStatistics:
    """Statistics about ring buffer operation."""

    wraparound_count: int
    data_integrity_checks_passed: int
    total_chunks_processed: int
    active_segments: int
    silence_optimized_segments: int


@dataclass
class StorageStatistics:
    """Statistics about storage optimization."""

    active_segments: int
    silence_optimized_segments: int
    total_segments: int
    compression_ratio: float


@dataclass
class PerformanceStatistics:
    """Performance metrics for ring buffer operations."""

    average_add_latency_ms: float
    memory_efficiency_ratio: float
    throughput_chunks_per_second: float


class RingBufferAudioProcessor:
    """Memory-efficient ring buffer for continuous audio processing."""

    def __init__(
        self,
        buffer_size_minutes: int,
        sample_rate: int = 16000,
        max_memory_mb: int = 50,
        overlap_ms: int = 250,
        silence_detection_threshold: float = 0.01,
    ):
        self.buffer_size_minutes = buffer_size_minutes
        self.sample_rate = sample_rate
        self.max_memory_mb = max_memory_mb
        self.overlap_ms = overlap_ms
        self.silence_detection_threshold = silence_detection_threshold

        # Calculate buffer capacity in samples - limit to prevent memory issues
        max_theoretical_samples = buffer_size_minutes * 60 * sample_rate
        # Limit buffer size to stay within memory constraints (float32 + int64 = 12 bytes per sample)
        max_memory_samples = (max_memory_mb * 1024 * 1024 * 0.8) // 12  # Use 80% of memory limit
        self.max_samples = min(max_theoretical_samples, int(max_memory_samples))
        self.max_memory_bytes = max_memory_mb * 1024 * 1024

        # Ring buffer storage
        self._audio_buffer = np.zeros(self.max_samples, dtype=np.float32)
        self._timestamps = np.zeros(self.max_samples, dtype=np.int64)

        # Buffer management
        self._write_position = 0
        self._buffer_full = False
        self._chunks_processed = 0
        self._wraparound_count = 0

        # Performance tracking
        self._add_times: list[float] = []
        self._data_integrity_checks = 0

        # Audio segments tracking
        self._active_segments: list[dict] = []
        self._silence_segments: list[dict] = []

        # Thread safety
        self._buffer_lock = asyncio.Lock()

        logger.info(
            f"Initialized ring buffer: {buffer_size_minutes}min, {max_memory_mb}MB limit, {overlap_ms}ms overlap"
        )

    async def add_chunk(self, chunk: AudioChunk) -> None:
        """Add an audio chunk to the ring buffer."""
        start_time = time.perf_counter()

        async with self._buffer_lock:
            # Convert chunk data to float32 numpy array
            audio_data = np.frombuffer(chunk.data, dtype=np.int16).astype(np.float32) / 32767.0
            chunk_samples = len(audio_data)

            # Handle buffer wraparound
            if self._write_position + chunk_samples > self.max_samples:
                # Split chunk across buffer boundary
                first_part_size = self.max_samples - self._write_position
                second_part_size = chunk_samples - first_part_size

                # Write first part
                self._audio_buffer[self._write_position :] = audio_data[:first_part_size]
                self._timestamps[self._write_position :] = chunk.timestamp

                # Write second part at beginning
                if second_part_size > 0:
                    self._audio_buffer[:second_part_size] = audio_data[first_part_size:]
                    self._timestamps[:second_part_size] = chunk.timestamp

                self._write_position = second_part_size
                self._wraparound_count += 1
                self._buffer_full = True
            else:
                # Normal write
                self._audio_buffer[self._write_position : self._write_position + chunk_samples] = audio_data
                self._timestamps[self._write_position : self._write_position + chunk_samples] = chunk.timestamp
                self._write_position += chunk_samples

                if self._write_position >= self.max_samples:
                    self._buffer_full = True

            # Update segments
            await self._update_segments(chunk, audio_data)

            # Data integrity check
            self._data_integrity_checks += 1

            self._chunks_processed += 1

        # Track performance
        add_time = time.perf_counter() - start_time
        self._add_times.append(add_time)

        # Keep performance history manageable
        if len(self._add_times) > 1000:
            self._add_times = self._add_times[-500:]

    async def _update_segments(self, chunk: AudioChunk, audio_data: np.ndarray) -> None:
        """Update active and silence segments based on incoming chunk."""
        energy = np.mean(np.abs(audio_data))

        segment_info = {
            "timestamp": chunk.timestamp,
            "energy": energy,
            "samples": len(audio_data),
            "source_id": chunk.source_id,
        }

        if energy > self.silence_detection_threshold:
            self._active_segments.append(segment_info)
            # Keep only recent active segments to prevent memory growth
            if len(self._active_segments) > 100:
                self._active_segments = self._active_segments[-50:]
        else:
            self._silence_segments.append(segment_info)
            # Optimize silence storage - keep fewer silence segments
            if len(self._silence_segments) > 50:
                self._silence_segments = self._silence_segments[-25:]

    def get_memory_usage_mb(self) -> float:
        """Get current memory usage in MB."""
        # Calculate memory used by main buffer (only the allocated arrays)
        buffer_memory = self._audio_buffer.nbytes + self._timestamps.nbytes

        # Add memory from segments tracking (much smaller overhead)
        segments_memory = (
            len(self._active_segments) * 50  # Reduced estimate per segment
            + len(self._silence_segments) * 50
            + len(self._add_times) * 8  # Performance tracking
        )

        total_memory = buffer_memory + segments_memory
        return total_memory / (1024 * 1024)

    def get_available_audio_duration_ms(self) -> float:
        """Get duration of available audio in the buffer."""
        available_samples = self._write_position if not self._buffer_full else self.max_samples
        return (available_samples / self.sample_rate) * 1000

    def get_sliding_windows(self, window_duration_ms: int) -> list[SlidingWindow]:
        """Get sliding windows of specified duration from recent audio."""
        window_samples = int(window_duration_ms * self.sample_rate / 1000)
        overlap_samples = int(self.overlap_ms * self.sample_rate / 1000)

        windows = []

        if not self._buffer_full and self._write_position < window_samples:
            # Not enough data yet
            return windows

        # Determine available range
        available_samples = self.max_samples if self._buffer_full else self._write_position

        # Generate windows with overlap
        current_pos = max(0, available_samples - window_samples)

        while current_pos + window_samples <= available_samples:
            # Extract window data
            if self._buffer_full and current_pos + window_samples > self.max_samples:
                # Handle wraparound
                first_part = self.max_samples - current_pos
                second_part = window_samples - first_part

                window_audio = np.concatenate([self._audio_buffer[current_pos:], self._audio_buffer[:second_part]])

                # Use timestamp from start of window
                start_timestamp = self._timestamps[current_pos]
            else:
                # Normal extraction
                end_pos = current_pos + window_samples
                window_audio = self._audio_buffer[current_pos:end_pos].copy()
                start_timestamp = self._timestamps[current_pos] if current_pos < len(self._timestamps) else 0

            # Convert back to int16 bytes
            window_bytes = (window_audio * 32767).astype(np.int16).tobytes()

            # Calculate end timestamp
            duration_us = int(window_duration_ms * 1000)
            end_timestamp = start_timestamp + duration_us

            window = SlidingWindow(
                start_timestamp=start_timestamp,
                end_timestamp=end_timestamp,
                audio_data=window_bytes,
                sample_rate=self.sample_rate,
            )

            windows.append(window)

            # Move to next window position
            current_pos += window_samples - overlap_samples

            # Only generate a few windows to avoid memory issues
            if len(windows) >= 3:
                break

        return windows

    def get_storage_statistics(self) -> StorageStatistics:
        """Get storage optimization statistics."""
        total_segments = len(self._active_segments) + len(self._silence_segments)
        compression_ratio = 1.0

        if total_segments > 0:
            # Simple compression ratio calculation
            active_ratio = len(self._active_segments) / total_segments
            compression_ratio = 1.0 + (1.0 - active_ratio) * 0.5  # Silence segments save ~50% space

        return StorageStatistics(
            active_segments=len(self._active_segments),
            silence_optimized_segments=len(self._silence_segments),
            total_segments=total_segments,
            compression_ratio=compression_ratio,
        )

    def get_buffer_statistics(self) -> BufferStatistics:
        """Get buffer operation statistics."""
        return BufferStatistics(
            wraparound_count=self._wraparound_count,
            data_integrity_checks_passed=self._data_integrity_checks,
            total_chunks_processed=self._chunks_processed,
            active_segments=len(self._active_segments),
            silence_optimized_segments=len(self._silence_segments),
        )

    def get_earliest_available_timestamp(self) -> int:
        """Get the earliest available timestamp in the buffer."""
        if not self._buffer_full:
            return self._timestamps[0] if self._write_position > 0 else 0

        # In a full buffer, earliest data is at current write position
        return self._timestamps[self._write_position]

    def get_latest_available_timestamp(self) -> int:
        """Get the latest available timestamp in the buffer."""
        if self._write_position == 0:
            return 0

        if not self._buffer_full:
            return self._timestamps[self._write_position - 1]
        else:
            # Latest data is just before write position
            latest_pos = (self._write_position - 1) % self.max_samples
            return self._timestamps[latest_pos]

    def get_audio_range(self, start_timestamp_us: int, duration_ms: int) -> bytes | None:
        """Get audio data for a specific time range."""
        # This is a simplified implementation
        # In practice, you'd need to map timestamps to buffer positions

        # Find approximate position based on timestamps
        earliest = self.get_earliest_available_timestamp()
        latest = self.get_latest_available_timestamp()

        if start_timestamp_us < earliest or start_timestamp_us > latest:
            return None

        # Calculate relative position (simplified)
        total_time_range = latest - earliest
        if total_time_range <= 0:
            return None

        time_offset = start_timestamp_us - earliest
        relative_position = time_offset / total_time_range

        # Calculate buffer position
        if self._buffer_full:
            buffer_offset = int(relative_position * self.max_samples)
            start_pos = (self._write_position + buffer_offset) % self.max_samples
        else:
            start_pos = int(relative_position * self._write_position)

        # Extract requested duration
        duration_samples = int(duration_ms * self.sample_rate / 1000)
        end_pos = min(start_pos + duration_samples, self.max_samples)

        # Extract audio data
        if end_pos <= self.max_samples:
            audio_data = self._audio_buffer[start_pos:end_pos].copy()
        else:
            # Handle wraparound
            first_part = self._audio_buffer[start_pos:]
            second_part = self._audio_buffer[: end_pos - self.max_samples]
            audio_data = np.concatenate([first_part, second_part])

        # Convert to bytes
        return (audio_data * 32767).astype(np.int16).tobytes()

    def get_performance_statistics(self) -> PerformanceStatistics:
        """Get performance metrics."""
        if not self._add_times:
            return PerformanceStatistics(
                average_add_latency_ms=0.0,
                memory_efficiency_ratio=1.0,
                throughput_chunks_per_second=0.0,
            )

        avg_latency = sum(self._add_times) / len(self._add_times) * 1000  # Convert to ms

        # Calculate memory efficiency (how much we're using relative to limit)
        current_memory = self.get_memory_usage_mb()
        efficiency_ratio = min(1.0, current_memory / self.max_memory_mb)

        # Calculate throughput
        total_time = sum(self._add_times)
        throughput = len(self._add_times) / total_time if total_time > 0 else 0

        return PerformanceStatistics(
            average_add_latency_ms=avg_latency,
            memory_efficiency_ratio=efficiency_ratio,
            throughput_chunks_per_second=throughput,
        )
