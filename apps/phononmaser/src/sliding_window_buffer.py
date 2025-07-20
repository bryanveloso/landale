"""Sliding window buffer for continuous audio processing with overlap management.

Manages overlapping audio windows to prevent word boundary fragmentation
during real-time transcription processing.
"""

import asyncio
import logging
from dataclasses import dataclass

import numpy as np

from audio_processor import AudioChunk

logger = logging.getLogger(__name__)


@dataclass
class ProcessingWindow:
    """A window of audio data ready for transcription processing."""

    start_timestamp: int  # Start time in milliseconds
    end_timestamp: int  # End time in milliseconds
    audio_data: bytes  # Raw audio data for this window
    chunk_ids: list[str]  # Source chunk IDs that contributed to this window


class SlidingWindowBuffer:
    """Sliding window buffer that maintains overlapping audio segments for processing."""

    def __init__(
        self,
        window_size_ms: int = 1500,
        overlap_ms: int = 250,
        sample_rate: int = 16000,
        max_windows: int = 10,
        silence_threshold: float = 0.01,
        vad_processor=None,  # Optional VAD processor for adaptive chunking
        speech_boundary_adjustment: bool = False,  # Enable VAD-based boundary adjustment
        adaptive_input: bool = False,  # Enable adaptive chunk input mode
    ):
        self.window_size_ms = window_size_ms
        self.overlap_ms = overlap_ms
        self.sample_rate = sample_rate
        self.max_windows = max_windows
        self.silence_threshold = silence_threshold
        self.vad_processor = vad_processor
        self.speech_boundary_adjustment = speech_boundary_adjustment
        self.adaptive_input = adaptive_input

        # Calculate step size (how far to advance between windows)
        self.step_size_ms = window_size_ms - overlap_ms

        # Internal buffer management
        self._audio_buffer: list[AudioChunk] = []
        self._processing_windows: list[ProcessingWindow] = []
        self._buffer_lock = asyncio.Lock()
        self._last_window_timestamp = 0

        # Buffer size limits
        self._max_buffer_duration_ms = window_size_ms * 3  # Keep 3 windows worth of raw data

    async def add_chunk(self, chunk: AudioChunk) -> None:
        """Add an audio chunk to the sliding window buffer."""
        async with self._buffer_lock:
            # Add chunk to buffer
            self._audio_buffer.append(chunk)

            # Sort buffer by timestamp to handle out-of-order chunks
            self._audio_buffer.sort(key=lambda c: c.timestamp)

            # Clean old chunks to manage memory
            await self._cleanup_old_chunks()

            # Generate new windows if enough data is available
            await self._generate_windows()

    def get_processing_windows(self) -> list[ProcessingWindow]:
        """Get available processing windows."""
        return self._processing_windows.copy()

    async def _cleanup_old_chunks(self) -> None:
        """Remove old chunks that are no longer needed."""
        if not self._audio_buffer:
            return

        # Calculate cutoff time - keep chunks within max buffer duration
        latest_timestamp = self._audio_buffer[-1].timestamp // 1000  # Convert to ms
        cutoff_timestamp = latest_timestamp - self._max_buffer_duration_ms
        cutoff_timestamp_us = cutoff_timestamp * 1000  # Convert back to microseconds

        # Remove chunks older than cutoff
        self._audio_buffer = [chunk for chunk in self._audio_buffer if chunk.timestamp >= cutoff_timestamp_us]

    async def _generate_windows(self) -> None:
        """Generate all possible processing windows from buffered chunks."""
        if not self._audio_buffer:
            return

        # Calculate buffer span
        first_timestamp = self._audio_buffer[0].timestamp // 1000  # Convert to ms
        last_timestamp = self._audio_buffer[-1].timestamp // 1000
        buffer_duration = last_timestamp - first_timestamp

        # Need at least one window size worth of data
        if buffer_duration < self.window_size_ms:
            logger.debug(f"Insufficient buffer duration: {buffer_duration}ms < {self.window_size_ms}ms")
            return

        # Clear existing windows and regenerate them all
        # This simplifies the logic and ensures consistency
        self._processing_windows.clear()

        # Generate all possible windows with proper step intervals
        window_start = first_timestamp
        windows_created = 0

        while window_start + self.window_size_ms <= last_timestamp:
            window_end = window_start + self.window_size_ms

            # Create window from chunks in this time range
            window = await self._create_window(window_start, window_end)

            if window and self._is_meaningful_window(window):
                self._processing_windows.append(window)
                windows_created += 1

                # Limit number of windows for memory management
                if len(self._processing_windows) >= self.max_windows:
                    break

            # Move to next window position with proper step size
            window_start += self.step_size_ms

        if windows_created > 0:
            logger.debug(f"Generated {windows_created} windows, total: {len(self._processing_windows)}")
            # Update last window timestamp to the last successful window
            self._last_window_timestamp = self._processing_windows[-1].start_timestamp

    async def _create_window(self, start_ms: int, end_ms: int) -> ProcessingWindow | None:
        """Create a processing window from chunks in the specified time range."""
        start_us = start_ms * 1000  # Convert to microseconds
        end_us = end_ms * 1000

        # Find chunks that overlap with this window
        overlapping_chunks = [
            chunk for chunk in self._audio_buffer if self._chunk_overlaps_window(chunk, start_us, end_us)
        ]

        if not overlapping_chunks:
            return None

        # Calculate total samples needed for this window
        window_samples = int(self.window_size_ms * self.sample_rate / 1000)
        window_audio = np.zeros(window_samples, dtype=np.int16)

        # Fill window with audio data from overlapping chunks
        chunk_ids = []
        for chunk in overlapping_chunks:
            chunk_start_ms = chunk.timestamp // 1000

            # Convert chunk data to samples
            chunk_audio = np.frombuffer(chunk.data, dtype=np.int16)

            # Calculate where this chunk data goes in the window
            offset_ms = max(0, chunk_start_ms - start_ms)
            offset_samples = int(offset_ms * self.sample_rate / 1000)

            # Calculate how much of this chunk to use
            available_samples = window_samples - offset_samples
            chunk_samples_to_use = min(len(chunk_audio), available_samples)

            if chunk_samples_to_use > 0:
                end_sample = offset_samples + chunk_samples_to_use
                window_audio[offset_samples:end_sample] = chunk_audio[:chunk_samples_to_use]
                chunk_ids.append(chunk.source_id)

        return ProcessingWindow(
            start_timestamp=start_ms,
            end_timestamp=end_ms,
            audio_data=window_audio.tobytes(),
            chunk_ids=chunk_ids,
        )

    def _chunk_overlaps_window(self, chunk: AudioChunk, window_start_us: int, window_end_us: int) -> bool:
        """Check if a chunk overlaps with a window time range."""
        # Estimate chunk duration (assuming 16-bit mono audio)
        bytes_per_sample = 2
        chunk_samples = len(chunk.data) // bytes_per_sample
        chunk_duration_us = int(chunk_samples / self.sample_rate * 1_000_000)

        chunk_start = chunk.timestamp
        chunk_end = chunk.timestamp + chunk_duration_us

        # Check for overlap
        return not (chunk_end <= window_start_us or chunk_start >= window_end_us)

    def _is_meaningful_window(self, window: ProcessingWindow) -> bool:
        """Check if a window contains meaningful audio content."""
        # Convert audio data to float for analysis
        audio_samples = np.frombuffer(window.audio_data, dtype=np.int16).astype(np.float32) / 32767.0

        # Check if window has sufficient audio energy
        max_amplitude = np.max(np.abs(audio_samples))

        logger.debug(
            f"Window {window.start_timestamp}-{window.end_timestamp}ms: max_amplitude={max_amplitude:.4f}, threshold={self.silence_threshold}"
        )

        return max_amplitude > self.silence_threshold

    async def reset(self) -> None:
        """Reset the sliding window buffer."""
        async with self._buffer_lock:
            self._audio_buffer.clear()
            self._processing_windows.clear()
            self._last_window_timestamp = 0

    def get_buffer_info(self) -> dict:
        """Get information about the current buffer state."""
        if not self._audio_buffer:
            return {
                "total_chunks": 0,
                "buffer_duration_ms": 0,
                "processing_windows": len(self._processing_windows),
                "oldest_timestamp": 0,
                "newest_timestamp": 0,
            }

        oldest_timestamp = self._audio_buffer[0].timestamp // 1000
        newest_timestamp = self._audio_buffer[-1].timestamp // 1000

        return {
            "total_chunks": len(self._audio_buffer),
            "buffer_duration_ms": newest_timestamp - oldest_timestamp,
            "processing_windows": len(self._processing_windows),
            "oldest_timestamp": oldest_timestamp,
            "newest_timestamp": newest_timestamp,
        }
