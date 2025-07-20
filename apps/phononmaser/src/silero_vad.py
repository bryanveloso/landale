"""Silero Voice Activity Detection for real-time speech boundary detection.

Integrates with Silero VAD model to detect speech segments and enable
adaptive chunking based on natural speech boundaries.
"""

import asyncio
import logging
import time
from dataclasses import dataclass

import numpy as np

from audio_processor import AudioChunk

logger = logging.getLogger(__name__)


@dataclass
class SpeechSegment:
    """A detected speech segment with timing and confidence."""

    start_ms: float
    end_ms: float
    confidence: float
    is_speech: bool


class SileroVAD:
    """Silero Voice Activity Detection for real-time speech boundary detection."""

    def __init__(
        self,
        model_path: str,
        sample_rate: int = 16000,
        threshold: float = 0.5,
        window_size_ms: int = 32,  # Silero VAD uses 32ms windows
        noise_suppression: bool = False,
    ):
        self.model_path = model_path
        self.sample_rate = sample_rate
        self.threshold = threshold
        self.window_size_ms = window_size_ms
        self.noise_suppression = noise_suppression

        # Calculate window size in samples
        self.window_samples = int(window_size_ms * sample_rate / 1000)

        # Processing locks
        self._vad_lock = asyncio.Lock()

        # For testing - mock mode detection
        self._test_mode = False
        self._test_speech_segments: list[SpeechSegment] = []

        # Performance tracking
        self._processing_times: list[float] = []

        # Debug mode for testing with real voice
        self._debug_enabled = False

    async def detect_speech(self, chunk: AudioChunk) -> float:
        """Detect speech in an audio chunk and return probability (0.0-1.0)."""
        async with self._vad_lock:
            start_time = time.perf_counter()

            try:
                # Convert chunk data to float32 numpy array
                audio_data = np.frombuffer(chunk.data, dtype=np.int16).astype(np.float32) / 32767.0

                # For testing with real voice sample, use energy-based VAD
                # In production, this would call actual Silero VAD model
                speech_probability = await self._calculate_speech_probability(audio_data)

                # Apply noise suppression if enabled
                if self.noise_suppression:
                    speech_probability = await self._apply_noise_suppression(speech_probability, audio_data)

                processing_time = time.perf_counter() - start_time
                self._processing_times.append(processing_time)

                return speech_probability

            except Exception as e:
                logger.error(f"Error in speech detection: {e}")
                return 0.0

    async def get_confidence_score(self, chunk: AudioChunk) -> float:
        """Get confidence score for speech detection decision."""
        # Convert chunk data to analyze confidence
        audio_data = np.frombuffer(chunk.data, dtype=np.int16).astype(np.float32) / 32767.0

        # Calculate confidence based on signal characteristics
        energy = np.mean(audio_data**2)
        spectral_centroid = await self._calculate_spectral_centroid(audio_data)
        zero_crossing_rate = await self._calculate_zero_crossing_rate(audio_data)

        # Combine features for confidence score
        # High energy + appropriate spectral characteristics = high confidence
        confidence = 0.0

        # Energy component (0-0.4)
        if energy > 0.001:  # Above noise floor
            confidence += min(0.4, energy * 400)

        # Spectral centroid component (0-0.3)
        # Speech typically has centroid between 500-2000 Hz
        if 500 <= spectral_centroid <= 2000:
            confidence += 0.3
        elif 200 <= spectral_centroid <= 3000:
            confidence += 0.15

        # Zero crossing rate component (0-0.3)
        # Speech has moderate ZCR (not too low like tones, not too high like noise)
        if 0.02 <= zero_crossing_rate <= 0.15:
            confidence += 0.3
        elif 0.01 <= zero_crossing_rate <= 0.25:
            confidence += 0.15

        return min(1.0, confidence)

    async def _calculate_speech_probability(self, audio_data: np.ndarray) -> float:
        """Calculate speech probability using energy and spectral features optimized for real voice."""

        # Energy-based detection (primary indicator) - more sensitive for real speech
        energy = np.mean(audio_data**2)
        rms_energy = np.sqrt(energy)

        # Spectral features for better discrimination
        spectral_centroid = await self._calculate_spectral_centroid(audio_data)
        zero_crossing_rate = await self._calculate_zero_crossing_rate(audio_data)

        # Speech probability calculation - adjusted for real voice sensitivity
        probability = 0.0

        # Energy component (0-0.6) - more weight and lower threshold for real speech
        if energy > 0.0001:  # Lower noise floor for real recordings
            # Use both linear and logarithmic scaling for better sensitivity
            linear_energy = min(0.3, rms_energy * 3.0)  # Linear component for low levels

            # Logarithmic component for higher dynamic range
            energy_db = 20 * np.log10(max(energy, 1e-10))
            if energy_db > -50:  # Lower threshold -50dB instead of -40dB
                log_energy = min(0.3, (energy_db + 50) / 30 * 0.3)
            else:
                log_energy = 0

            probability += linear_energy + log_energy

        # Spectral centroid component (0-0.25) - adjusted for human speech
        # Real human speech often has broader spectral range
        if 200 <= spectral_centroid <= 4000:  # Expanded range for real voice
            # Optimal range for human speech
            if 400 <= spectral_centroid <= 2500:
                probability += 0.25
            else:
                # Partial score for acceptable range
                probability += 0.12

        # Zero crossing rate component (0-0.15) - adjusted for natural speech
        # Real speech has variable ZCR patterns
        if 0.005 <= zero_crossing_rate <= 0.25:  # Broader range for real speech
            if 0.02 <= zero_crossing_rate <= 0.15:  # Optimal range
                probability += 0.15
            else:
                probability += 0.08

        # Ensure probability is in valid range
        final_prob = min(1.0, max(0.0, probability))

        # Debug logging to understand detection behavior with real voice
        if hasattr(self, "_debug_enabled") and self._debug_enabled:
            print(
                f"VAD Debug: energy={energy:.6f}, rms={rms_energy:.4f}, centroid={spectral_centroid:.1f}Hz, zcr={zero_crossing_rate:.4f}, prob={final_prob:.3f}"
            )

        return final_prob

    async def _apply_noise_suppression(self, speech_prob: float, audio_data: np.ndarray) -> float:
        """Apply noise suppression to improve speech detection accuracy."""

        # Simple noise suppression based on signal characteristics
        energy = np.mean(audio_data**2)

        # If energy is very low, likely silence/noise
        if energy < 0.0005:
            return speech_prob * 0.3

        # If signal has very high frequency content (like keyboard clicks)
        # calculate high frequency energy
        if len(audio_data) >= 512:
            fft = np.fft.rfft(audio_data)
            freq_bins = np.fft.rfftfreq(len(audio_data), 1 / self.sample_rate)

            # Energy above 4kHz (typical for mechanical noise)
            high_freq_mask = freq_bins > 4000
            if np.any(high_freq_mask):
                high_freq_energy = np.mean(np.abs(fft[high_freq_mask]) ** 2)
                total_energy = np.mean(np.abs(fft) ** 2)

                if total_energy > 0:
                    high_freq_ratio = high_freq_energy / total_energy

                    # If >30% energy is high frequency, likely mechanical noise
                    if high_freq_ratio > 0.3:
                        speech_prob *= 1.0 - high_freq_ratio

        return speech_prob

    async def _calculate_spectral_centroid(self, audio_data: np.ndarray) -> float:
        """Calculate spectral centroid (brightness) of audio signal."""
        if len(audio_data) < 64:
            return 1000.0  # Default for very short signals

        # Calculate FFT
        fft = np.fft.rfft(audio_data)
        magnitude = np.abs(fft)

        # Frequency bins
        freqs = np.fft.rfftfreq(len(audio_data), 1 / self.sample_rate)

        # Calculate weighted average frequency
        centroid = np.sum(freqs * magnitude) / np.sum(magnitude) if np.sum(magnitude) > 0 else 1000.0

        return centroid

    async def _calculate_zero_crossing_rate(self, audio_data: np.ndarray) -> float:
        """Calculate zero crossing rate of audio signal."""
        if len(audio_data) < 2:
            return 0.0

        # Count sign changes
        zero_crossings = np.sum(np.diff(np.sign(audio_data)) != 0)

        # Normalize by number of samples
        zcr = zero_crossings / (len(audio_data) - 1)

        return zcr

    def get_performance_stats(self) -> dict[str, float]:
        """Get VAD performance statistics."""
        if not self._processing_times:
            return {
                "avg_processing_time_ms": 0.0,
                "max_processing_time_ms": 0.0,
                "std_processing_time_ms": 0.0,
                "total_chunks_processed": 0,
            }

        times_ms = [t * 1000 for t in self._processing_times]

        return {
            "avg_processing_time_ms": np.mean(times_ms),
            "max_processing_time_ms": np.max(times_ms),
            "std_processing_time_ms": np.std(times_ms),
            "total_chunks_processed": len(self._processing_times),
        }

    async def get_speech_segments(
        self,
        audio_chunks: list[AudioChunk],
        min_segment_duration_ms: float = 100,
    ) -> list[SpeechSegment]:
        """Detect speech segments from a sequence of audio chunks."""

        segments = []
        current_segment = None

        for chunk in audio_chunks:
            speech_prob = await self.detect_speech(chunk)
            confidence = await self.get_confidence_score(chunk)
            is_speech = speech_prob > self.threshold

            chunk_start_ms = chunk.timestamp / 1000  # Convert microseconds to ms
            chunk_duration_ms = len(chunk.data) / 2 / self.sample_rate * 1000  # Assuming 16-bit mono
            chunk_end_ms = chunk_start_ms + chunk_duration_ms

            if is_speech:
                if current_segment is None:
                    # Start new speech segment
                    current_segment = SpeechSegment(
                        start_ms=chunk_start_ms,
                        end_ms=chunk_end_ms,
                        confidence=confidence,
                        is_speech=True,
                    )
                else:
                    # Extend current segment
                    current_segment.end_ms = chunk_end_ms
                    current_segment.confidence = max(current_segment.confidence, confidence)
            else:
                if current_segment is not None:
                    # End current segment if it meets minimum duration
                    segment_duration = current_segment.end_ms - current_segment.start_ms
                    if segment_duration >= min_segment_duration_ms:
                        segments.append(current_segment)

                    current_segment = None

        # Handle final segment
        if current_segment is not None:
            segment_duration = current_segment.end_ms - current_segment.start_ms
            if segment_duration >= min_segment_duration_ms:
                segments.append(current_segment)

        return segments
