"""Adaptive chunking using VAD-guided speech boundary detection.

Creates variable-sized audio chunks that align with natural speech boundaries
to prevent word fragmentation during real-time transcription processing.
"""

import asyncio
import logging
from dataclasses import dataclass

import numpy as np

from audio_processor import AudioChunk
from silero_vad import SileroVAD

logger = logging.getLogger(__name__)


@dataclass
class ChunkBoundary:
    """A detected chunk boundary with timing and confidence."""

    timestamp_ms: float
    boundary_type: str  # 'speech_start', 'speech_end', 'silence_gap', 'forced'
    confidence: float
    speech_probability: float


class AdaptiveChunker:
    """Adaptive chunker that uses VAD to create speech-aligned variable-sized chunks."""

    def __init__(
        self,
        vad_model_path: str,
        target_chunk_duration_ms: int = 1500,
        min_chunk_duration_ms: int = 800,
        max_chunk_duration_ms: int = 2500,
        vad_threshold: float = 0.1,
        speech_boundary_tolerance_ms: int = 200,
        silence_extension_ms: int = 100,
        sample_rate: int = 16000,
    ):
        self.target_chunk_duration_ms = target_chunk_duration_ms
        self.min_chunk_duration_ms = min_chunk_duration_ms
        self.max_chunk_duration_ms = max_chunk_duration_ms
        self.speech_boundary_tolerance_ms = speech_boundary_tolerance_ms
        self.silence_extension_ms = silence_extension_ms
        self.sample_rate = sample_rate

        # Initialize VAD processor
        self.vad = SileroVAD(
            model_path=vad_model_path,
            sample_rate=sample_rate,
            threshold=vad_threshold,
        )

        # Internal buffering
        self._audio_buffer: list[AudioChunk] = []
        self._buffer_lock = asyncio.Lock()
        self._speech_states: list[dict] = []  # Track speech/silence states
        self._last_boundary_timestamp = 0.0

        # Chunk creation state
        self._current_chunk_start = 0.0
        self._pending_boundaries: list[ChunkBoundary] = []

    async def process_chunk(self, chunk: AudioChunk) -> list[AudioChunk]:
        """Process an input chunk and return any completed adaptive chunks."""
        async with self._buffer_lock:
            # Initialize chunk start with first chunk timestamp if not set
            if self._current_chunk_start == 0.0 and self._audio_buffer:
                self._current_chunk_start = self._audio_buffer[0].timestamp / 1000
            elif self._current_chunk_start == 0.0:
                self._current_chunk_start = chunk.timestamp / 1000

            # Add chunk to buffer
            self._audio_buffer.append(chunk)

            # Analyze speech activity for this chunk
            await self._analyze_speech_activity(chunk)

            # Check if we can create any adaptive chunks
            completed_chunks = await self._create_adaptive_chunks()

            return completed_chunks

    async def finalize(self) -> list[AudioChunk]:
        """Finalize processing and return any remaining buffered audio as chunks."""
        async with self._buffer_lock:
            final_chunks = []

            # Force completion of any remaining buffered audio
            if self._audio_buffer:
                remaining_chunk = await self._create_forced_chunk()
                if remaining_chunk:
                    final_chunks.append(remaining_chunk)

            # Clear internal state
            self._audio_buffer.clear()
            self._speech_states.clear()
            self._pending_boundaries.clear()

            return final_chunks

    async def _analyze_speech_activity(self, chunk: AudioChunk) -> None:
        """Analyze speech activity for the given chunk and update state."""
        # For now, use energy-based speech detection until real VAD is integrated
        # Convert chunk data to numpy array for analysis
        audio_data = np.frombuffer(chunk.data, dtype=np.int16).astype(np.float32) / 32767.0

        # Simple energy-based speech detection
        energy = np.mean(audio_data**2)

        # Use microphone-specific thresholds
        from microphone_profiles import get_current_microphone

        mic = get_current_microphone()
        speech_threshold = mic.profile.speech_detection_threshold

        # Simulate speech probability based on energy
        if energy > speech_threshold:
            speech_probability = min(0.9, energy / speech_threshold)
        else:
            speech_probability = max(0.1, energy / speech_threshold * 0.5)

        confidence = 0.8 if abs(speech_probability - 0.5) > 0.3 else 0.6

        chunk_start_ms = chunk.timestamp / 1000
        chunk_duration_ms = len(chunk.data) / 2 / self.sample_rate * 1000  # Assuming 16-bit mono
        chunk_end_ms = chunk_start_ms + chunk_duration_ms

        # Store speech state for boundary detection
        speech_state = {
            "start_ms": chunk_start_ms,
            "end_ms": chunk_end_ms,
            "speech_probability": speech_probability,
            "confidence": confidence,
            "is_speech": speech_probability > 0.5,  # Threshold for speech detection
        }

        self._speech_states.append(speech_state)

        # Detect boundaries based on speech transitions
        await self._detect_speech_boundaries()

        # Limit memory usage - keep only recent speech states
        max_states = 100  # Keep ~5 seconds of history at 50ms chunks
        if len(self._speech_states) > max_states:
            self._speech_states = self._speech_states[-max_states:]

    async def _detect_speech_boundaries(self) -> None:
        """Detect potential chunk boundaries based on speech activity transitions."""
        if len(self._speech_states) < 2:
            return

        current_state = self._speech_states[-1]
        previous_state = self._speech_states[-2]

        # Detect speech start (silence -> speech transition)
        if not previous_state["is_speech"] and current_state["is_speech"]:
            boundary = ChunkBoundary(
                timestamp_ms=current_state["start_ms"],
                boundary_type="speech_start",
                confidence=current_state["confidence"],
                speech_probability=current_state["speech_probability"],
            )
            self._pending_boundaries.append(boundary)

        # Detect speech end (speech -> silence transition)
        elif previous_state["is_speech"] and not current_state["is_speech"]:
            boundary = ChunkBoundary(
                timestamp_ms=previous_state["end_ms"],
                boundary_type="speech_end",
                confidence=previous_state["confidence"],
                speech_probability=previous_state["speech_probability"],
            )
            self._pending_boundaries.append(boundary)

        # Detect sustained silence gaps (potential natural break points)
        if len(self._speech_states) >= 5:  # Look at 5 recent states
            recent_states = self._speech_states[-5:]
            if all(not state["is_speech"] for state in recent_states):
                # Found sustained silence - mark as gap boundary
                gap_center = (recent_states[0]["start_ms"] + recent_states[-1]["end_ms"]) / 2
                boundary = ChunkBoundary(
                    timestamp_ms=gap_center,
                    boundary_type="silence_gap",
                    confidence=0.8,  # High confidence for silence gaps
                    speech_probability=0.0,
                )
                self._pending_boundaries.append(boundary)

    async def _create_adaptive_chunks(self) -> list[AudioChunk]:
        """Create adaptive chunks based on detected boundaries and duration constraints."""
        completed_chunks = []

        if not self._audio_buffer:
            return completed_chunks

        # Calculate current buffer duration
        buffer_start_ms = self._audio_buffer[0].timestamp / 1000
        last_chunk = self._audio_buffer[-1]
        last_chunk_duration_ms = len(last_chunk.data) / 2 / self.sample_rate * 1000
        buffer_end_ms = (last_chunk.timestamp / 1000) + last_chunk_duration_ms
        buffer_duration = buffer_end_ms - buffer_start_ms

        # Check if we have enough buffer to make decisions
        if buffer_duration < self.min_chunk_duration_ms:
            return completed_chunks

        # Find optimal chunk boundaries
        current_chunk_duration = buffer_end_ms - self._current_chunk_start

        # Case 1: Current chunk has reached maximum duration - force boundary
        if current_chunk_duration >= self.max_chunk_duration_ms:
            # Ensure we don't violate minimum duration for next chunk
            optimal_end = min(buffer_end_ms, self._current_chunk_start + self.max_chunk_duration_ms)
            chunk = await self._create_chunk_at_timestamp(optimal_end, "forced")
            if chunk:
                completed_chunks.append(chunk)

        # Case 2: Look for optimal boundary near target duration
        elif current_chunk_duration >= self.target_chunk_duration_ms - self.speech_boundary_tolerance_ms:
            optimal_boundary = await self._find_optimal_boundary()
            if optimal_boundary:
                chunk = await self._create_chunk_at_timestamp(
                    optimal_boundary.timestamp_ms, optimal_boundary.boundary_type
                )
                if chunk:
                    completed_chunks.append(chunk)
            else:
                # No optimal boundary found, but we're close to target - try to create chunk anyway
                # if we have enough buffer for target duration
                if current_chunk_duration >= self.target_chunk_duration_ms:
                    target_end = self._current_chunk_start + self.target_chunk_duration_ms
                    chunk = await self._create_chunk_at_timestamp(target_end, "target_duration")
                    if chunk:
                        completed_chunks.append(chunk)

        # Case 3: Force chunk if we've exceeded target + tolerance significantly
        elif current_chunk_duration >= self.target_chunk_duration_ms + self.speech_boundary_tolerance_ms:
            # Find nearest reasonable boundary or force at current position
            fallback_boundary = await self._find_fallback_boundary()
            if fallback_boundary:
                chunk = await self._create_chunk_at_timestamp(
                    fallback_boundary.timestamp_ms, fallback_boundary.boundary_type
                )
                if chunk:
                    completed_chunks.append(chunk)

        return completed_chunks

    async def _find_optimal_boundary(self) -> ChunkBoundary | None:
        """Find the optimal chunk boundary near the target duration."""
        if not self._pending_boundaries:
            return None

        target_timestamp = self._current_chunk_start + self.target_chunk_duration_ms
        tolerance = self.speech_boundary_tolerance_ms

        # Find boundaries within tolerance of target
        candidates = [
            boundary
            for boundary in self._pending_boundaries
            if abs(boundary.timestamp_ms - target_timestamp) <= tolerance
            and boundary.timestamp_ms > self._current_chunk_start + self.min_chunk_duration_ms
        ]

        if not candidates:
            return None

        # Prioritize boundary types: speech_end > silence_gap > speech_start
        priority_order = {"speech_end": 3, "silence_gap": 2, "speech_start": 1}

        # Sort by priority and confidence
        candidates.sort(
            key=lambda b: (
                priority_order.get(b.boundary_type, 0),
                b.confidence,
                -abs(b.timestamp_ms - target_timestamp),  # Prefer closer to target
            ),
            reverse=True,
        )

        return candidates[0]

    async def _find_fallback_boundary(self) -> ChunkBoundary | None:
        """Find a fallback boundary when no optimal boundary is available."""
        if not self._audio_buffer:
            return None

        # Use the most recent buffer position as fallback
        buffer_end_ms = self._audio_buffer[-1].timestamp / 1000

        # Check if we have any pending boundaries we can use
        usable_boundaries = [
            boundary
            for boundary in self._pending_boundaries
            if boundary.timestamp_ms > self._current_chunk_start + self.min_chunk_duration_ms
        ]

        if usable_boundaries:
            # Use the earliest available boundary
            usable_boundaries.sort(key=lambda b: b.timestamp_ms)
            return usable_boundaries[0]

        # Create forced boundary at current buffer end
        return ChunkBoundary(
            timestamp_ms=buffer_end_ms,
            boundary_type="forced",
            confidence=0.5,
            speech_probability=0.0,
        )

    async def _create_chunk_at_timestamp(self, end_timestamp_ms: float, boundary_type: str) -> AudioChunk | None:
        """Create a chunk from current start position to the specified end timestamp."""
        chunk_start_ms = self._current_chunk_start
        chunk_duration = end_timestamp_ms - chunk_start_ms

        # Validate chunk duration - if too short, extend to minimum
        if chunk_duration < self.min_chunk_duration_ms:
            # For forced boundaries, extend to minimum duration
            if boundary_type == "forced" or not self._audio_buffer:
                end_timestamp_ms = chunk_start_ms + self.min_chunk_duration_ms
                chunk_duration = self.min_chunk_duration_ms
            else:
                return None

        # Find audio chunks that overlap with this time range
        start_timestamp_us = int(chunk_start_ms * 1000)
        end_timestamp_us = int(end_timestamp_ms * 1000)

        overlapping_chunks = [
            chunk
            for chunk in self._audio_buffer
            if chunk.timestamp >= start_timestamp_us and chunk.timestamp < end_timestamp_us
        ]

        if not overlapping_chunks:
            return None

        # Ensure we have enough audio data to meet minimum duration
        total_audio_duration = 0
        for chunk in overlapping_chunks:
            chunk_duration_ms = len(chunk.data) / 2 / self.sample_rate * 1000
            total_audio_duration += chunk_duration_ms

        if total_audio_duration < self.min_chunk_duration_ms * 0.8:  # Allow some tolerance
            return None

        # Concatenate audio data from overlapping chunks
        combined_audio = await self._concatenate_audio_chunks(overlapping_chunks, start_timestamp_us, end_timestamp_us)

        if not combined_audio:
            return None

        # Create the adaptive chunk
        adaptive_chunk = AudioChunk(
            timestamp=start_timestamp_us,
            format=overlapping_chunks[0].format,
            data=combined_audio,
            source_id=f"adaptive_{boundary_type}_{int(chunk_start_ms)}_{int(end_timestamp_ms)}",
        )

        # Update state for next chunk
        self._current_chunk_start = end_timestamp_ms
        self._last_boundary_timestamp = end_timestamp_ms

        # Clean up processed boundaries
        self._pending_boundaries = [
            boundary for boundary in self._pending_boundaries if boundary.timestamp_ms > end_timestamp_ms
        ]

        # Clean up processed audio chunks
        self._audio_buffer = [chunk for chunk in self._audio_buffer if chunk.timestamp >= end_timestamp_us]

        logger.debug(f"Created adaptive chunk: {chunk_duration:.1f}ms ({boundary_type})")

        return adaptive_chunk

    async def _create_forced_chunk(self) -> AudioChunk | None:
        """Create a chunk from any remaining buffered audio."""
        if not self._audio_buffer:
            return None

        # Calculate remaining duration
        start_timestamp_us = self._audio_buffer[0].timestamp
        end_timestamp_us = self._audio_buffer[-1].timestamp

        # Calculate end time including the last chunk's duration
        last_chunk = self._audio_buffer[-1]
        last_chunk_duration_ms = len(last_chunk.data) / 2 / self.sample_rate * 1000
        end_timestamp_us += int(last_chunk_duration_ms * 1000)

        # Check if remaining duration meets minimum requirements
        # Allow shorter final chunks to preserve audio completeness
        remaining_duration_ms = (end_timestamp_us - start_timestamp_us) / 1000
        min_final_duration = min(self.min_chunk_duration_ms * 0.5, 200)  # 50% of min or 200ms minimum
        if remaining_duration_ms < min_final_duration:
            logger.debug(f"Skipping final chunk: {remaining_duration_ms:.1f}ms < {min_final_duration}ms minimum")
            return None

        # Concatenate all remaining audio
        combined_audio = await self._concatenate_audio_chunks(self._audio_buffer, start_timestamp_us, end_timestamp_us)

        if not combined_audio:
            return None

        return AudioChunk(
            timestamp=start_timestamp_us,
            format=self._audio_buffer[0].format,
            data=combined_audio,
            source_id=f"adaptive_final_{start_timestamp_us}_{end_timestamp_us}",
        )

    async def _concatenate_audio_chunks(self, chunks: list[AudioChunk], start_us: int, end_us: int) -> bytes | None:
        """Concatenate audio data from multiple chunks within the specified time range."""
        if not chunks:
            return None

        # Sort chunks by timestamp
        chunks = sorted(chunks, key=lambda c: c.timestamp)

        audio_segments = []

        for chunk in chunks:
            chunk_start_us = chunk.timestamp
            chunk_duration_ms = len(chunk.data) / 2 / self.sample_rate * 1000
            chunk_end_us = chunk_start_us + int(chunk_duration_ms * 1000)

            # Calculate overlap with desired time range
            overlap_start = max(start_us, chunk_start_us)
            overlap_end = min(end_us, chunk_end_us)

            if overlap_start >= overlap_end:
                continue  # No overlap

            # Extract the relevant portion of this chunk
            audio_data = np.frombuffer(chunk.data, dtype=np.int16)

            # Calculate sample indices for the overlap
            chunk_duration_samples = len(audio_data)
            samples_per_us = self.sample_rate / 1_000_000

            start_sample_offset = int((overlap_start - chunk_start_us) * samples_per_us)
            end_sample_offset = int((overlap_end - chunk_start_us) * samples_per_us)

            # Ensure indices are within bounds
            start_sample_offset = max(0, min(start_sample_offset, chunk_duration_samples))
            end_sample_offset = max(start_sample_offset, min(end_sample_offset, chunk_duration_samples))

            if start_sample_offset < end_sample_offset:
                segment = audio_data[start_sample_offset:end_sample_offset]
                audio_segments.append(segment)

        if not audio_segments:
            return None

        # Concatenate all segments
        combined_audio = np.concatenate(audio_segments)

        return combined_audio.astype(np.int16).tobytes()

    def get_statistics(self) -> dict:
        """Get adaptive chunking statistics."""
        return {
            "buffer_chunks": len(self._audio_buffer),
            "pending_boundaries": len(self._pending_boundaries),
            "speech_states": len(self._speech_states),
            "current_chunk_start_ms": self._current_chunk_start,
            "last_boundary_timestamp_ms": self._last_boundary_timestamp,
            "target_duration_ms": self.target_chunk_duration_ms,
            "min_duration_ms": self.min_chunk_duration_ms,
            "max_duration_ms": self.max_chunk_duration_ms,
        }
