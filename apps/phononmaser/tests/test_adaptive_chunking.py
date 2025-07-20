"""TDD tests for adaptive chunking using VAD-guided speech boundaries.

Tests adaptive chunking that uses Silero VAD to detect natural speech
boundaries and create variable-sized chunks that align with speech patterns
to prevent word fragmentation during streaming transcription.
"""

import sys
import wave
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from audio_processor import AudioChunk, AudioFormat
from microphone_profiles import get_current_microphone


class TestAdaptiveChunking:
    """Test adaptive chunking with VAD-guided speech boundary detection."""

    @pytest.mark.asyncio
    async def test_adaptive_chunking_creates_speech_aligned_segments(self, real_audio_context, whisper_test_config):
        """Test that adaptive chunking creates segments aligned with natural speech boundaries."""
        # This test will FAIL initially because AdaptiveChunker doesn't exist yet

        from adaptive_chunker import AdaptiveChunker

        # Get microphone-optimized configuration
        mic = get_current_microphone()
        vad_config = mic.get_vad_config()
        chunker_config = mic.get_adaptive_chunker_config()

        chunker = AdaptiveChunker(
            vad_model_path=whisper_test_config["vad_model_path"],
            target_chunk_duration_ms=1500,  # Target 1.5 second chunks
            min_chunk_duration_ms=800,  # Minimum 800ms chunks
            max_chunk_duration_ms=2500,  # Maximum 2.5 second chunks
            vad_threshold=vad_config["threshold"],  # Microphone-optimized threshold
            speech_boundary_tolerance_ms=chunker_config["speech_boundary_tolerance_ms"],
        )

        real_audio_context.register_processor(chunker)

        # Load real voice sample for speech boundary detection
        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"

        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            # Downsample from 48kHz to 16kHz (every 3rd sample)
            audio_data = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Simulate streaming audio chunks (50ms each for fine-grained control)
        chunk_duration_ms = 50
        chunk_samples = int(chunk_duration_ms * 16)

        input_chunks = []
        for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
            chunk_data = audio_data[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,  # microseconds
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"stream_chunk_{i // chunk_samples}",
            )
            input_chunks.append(chunk)

        # Process chunks through adaptive chunker
        adaptive_chunks = []
        for chunk in input_chunks:
            result_chunks = await chunker.process_chunk(chunk)
            adaptive_chunks.extend(result_chunks)

        # Finalize any remaining buffered audio
        final_chunks = await chunker.finalize()
        adaptive_chunks.extend(final_chunks)

        # Verify adaptive chunking behavior
        assert len(adaptive_chunks) >= 2, f"Should create multiple adaptive chunks, got {len(adaptive_chunks)}"

        # Verify chunk durations are within expected ranges
        for i, chunk in enumerate(adaptive_chunks):
            chunk_audio = np.frombuffer(chunk.data, dtype=np.int16)
            chunk_duration_ms = len(chunk_audio) / 16  # Convert samples to ms

            # Allow final chunk to be shorter to preserve audio completeness
            is_final_chunk = i == len(adaptive_chunks) - 1
            min_duration = 200 if is_final_chunk else 800

            assert min_duration <= chunk_duration_ms <= 2500, (
                f"Chunk {i} duration {chunk_duration_ms}ms should be within {min_duration}-2500ms range"
            )

        # Verify chunks are aligned with speech boundaries (not just time-based)
        # Speech-aligned chunks should have better start/end characteristics
        for i, chunk in enumerate(adaptive_chunks):
            chunk_audio = np.frombuffer(chunk.data, dtype=np.int16).astype(np.float32) / 32767.0

            # Check start energy (should be reasonable for speech start)
            start_energy = np.mean(np.abs(chunk_audio[:800]))  # First 50ms
            end_energy = np.mean(np.abs(chunk_audio[-800:]))  # Last 50ms

            # Speech-aligned chunks should start and end with meaningful audio
            # (not necessarily silence, but reasonable energy transitions)
            # Use microphone-specific threshold for meaningful boundary detection
            mic = get_current_microphone()
            energy_threshold = mic.get_test_thresholds()["energy_threshold"]

            # Final chunk may have lower energy due to speech trailing off - use more lenient validation
            is_final_chunk = i == len(adaptive_chunks) - 1
            if is_final_chunk:
                # For final chunks, accept lower energy levels or use background noise threshold
                background_threshold = mic.profile.background_noise_threshold
                effective_threshold = min(energy_threshold, background_threshold * 2)  # 2x background noise

                assert start_energy > effective_threshold or end_energy > effective_threshold, (
                    f"Final chunk {i} should have meaningful audio content at boundaries "
                    f"(start: {start_energy:.8f}, end: {end_energy:.8f}, threshold: {effective_threshold:.8f}) "
                    f"for {mic.get_microphone_info()}"
                )
            else:
                assert start_energy > energy_threshold or end_energy > energy_threshold, (
                    f"Chunk {i} should have meaningful audio content at boundaries "
                    f"(start: {start_energy:.8f}, end: {end_energy:.8f}, threshold: {energy_threshold:.8f}) "
                    f"for {mic.get_microphone_info()}"
                )

        # Verify total duration is preserved within reasonable bounds
        # Adaptive chunking may sacrifice some audio to align with speech boundaries
        total_input_duration = len(audio_data) / 16
        total_adaptive_duration = sum(len(np.frombuffer(chunk.data, dtype=np.int16)) / 16 for chunk in adaptive_chunks)

        duration_difference = abs(total_adaptive_duration - total_input_duration)
        # Allow up to 1% duration difference for speech-aligned chunking
        max_acceptable_difference = max(500, total_input_duration * 0.01)  # 500ms minimum or 1% of total
        assert duration_difference < max_acceptable_difference, (
            f"Total duration should be preserved within {max_acceptable_difference:.1f}ms, "
            f"diff: {duration_difference}ms ({duration_difference / total_input_duration * 100:.2f}%)"
        )

    @pytest.mark.asyncio
    async def test_adaptive_chunking_respects_minimum_and_maximum_durations(
        self, real_audio_context, whisper_test_config
    ):
        """Test that adaptive chunking enforces minimum and maximum chunk duration limits."""

        from adaptive_chunker import AdaptiveChunker

        chunker = AdaptiveChunker(
            vad_model_path=whisper_test_config["vad_model_path"],
            target_chunk_duration_ms=1000,  # Target 1 second chunks
            min_chunk_duration_ms=600,  # Minimum 600ms
            max_chunk_duration_ms=1800,  # Maximum 1.8 seconds
            vad_threshold=0.15,
            speech_boundary_tolerance_ms=150,
        )

        # Load real voice sample and take first 6 seconds
        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            # Downsample from 48kHz to 16kHz (every 3rd sample)
            audio_data = audio_48k[::3]

        # Skip initial silence and take 6 seconds of actual speech (starting from 1 second)
        speech_start_samples = 1 * 16000  # Skip first 1 second of silence
        speech_duration_samples = 6 * 16000  # Take 6 seconds of speech
        test_audio = audio_data[speech_start_samples : speech_start_samples + speech_duration_samples]
        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Process in small streaming chunks
        chunk_duration_ms = 40  # 40ms chunks
        chunk_samples = int(chunk_duration_ms * 16)

        adaptive_chunks = []
        for i in range(0, len(test_audio) - chunk_samples, chunk_samples):
            chunk_data = test_audio[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"duration_test_{i // chunk_samples}",
            )

            result_chunks = await chunker.process_chunk(chunk)
            adaptive_chunks.extend(result_chunks)

        # Finalize processing
        final_chunks = await chunker.finalize()
        adaptive_chunks.extend(final_chunks)

        # Verify all chunks respect duration limits
        for i, chunk in enumerate(adaptive_chunks):
            chunk_audio = np.frombuffer(chunk.data, dtype=np.int16)
            chunk_duration_ms = len(chunk_audio) / 16

            assert 600 <= chunk_duration_ms <= 1800, (
                f"Chunk {i} duration {chunk_duration_ms}ms violates limits [600ms, 1800ms]"
            )

        # Verify most chunks are close to target duration
        target_aligned_chunks = 0
        for chunk in adaptive_chunks:
            chunk_audio = np.frombuffer(chunk.data, dtype=np.int16)
            chunk_duration_ms = len(chunk_audio) / 16

            # Count chunks within 200ms of target (1000ms ± 200ms = 800-1200ms)
            if 800 <= chunk_duration_ms <= 1200:
                target_aligned_chunks += 1

        target_ratio = target_aligned_chunks / len(adaptive_chunks)
        assert target_ratio >= 0.5, f"At least 50% of chunks should be near target duration, got {target_ratio:.1%}"

    @pytest.mark.asyncio
    async def test_adaptive_chunking_handles_silence_gaps_intelligently(
        self, real_audio_context, real_audio_generator, whisper_test_config
    ):
        """Test that adaptive chunking handles silence gaps by extending boundaries appropriately."""

        from adaptive_chunker import AdaptiveChunker

        chunker = AdaptiveChunker(
            vad_model_path=whisper_test_config["vad_model_path"],
            target_chunk_duration_ms=1200,
            min_chunk_duration_ms=700,
            max_chunk_duration_ms=2000,
            vad_threshold=0.12,
            speech_boundary_tolerance_ms=300,  # More tolerance for silence handling
            silence_extension_ms=150,  # Extend chunks into silence for natural breaks
        )

        # Create audio with speech -> silence -> speech pattern
        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"

        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            voice_audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0

        # Create pattern: speech -> 500ms silence -> speech
        speech_duration = 2.0 * 16000  # 2 seconds
        silence_duration = 0.5 * 16000  # 500ms

        if len(voice_audio) > speech_duration:
            speech1 = voice_audio[: int(speech_duration)]
            speech2 = voice_audio[: int(min(speech_duration, len(voice_audio) - speech_duration))]
        else:
            speech1 = voice_audio
            speech2 = voice_audio

        silence = np.zeros(int(silence_duration), dtype=np.float32)
        test_audio = np.concatenate([speech1, silence, speech2])

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Process through adaptive chunker
        chunk_duration_ms = 60  # 60ms streaming chunks
        chunk_samples = int(chunk_duration_ms * 16)

        adaptive_chunks = []
        for i in range(0, len(test_audio) - chunk_samples, chunk_samples):
            chunk_data = test_audio[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"silence_test_{i // chunk_samples}",
            )

            result_chunks = await chunker.process_chunk(chunk)
            adaptive_chunks.extend(result_chunks)

        final_chunks = await chunker.finalize()
        adaptive_chunks.extend(final_chunks)

        # Verify silence gap handling
        assert len(adaptive_chunks) >= 2, "Should create multiple chunks separated by silence"

        # Check that chunks end/start appropriately around silence gaps
        # At least one chunk should end during or just after the silence gap
        silence_start_ms = 2000  # 2 seconds into audio
        silence_end_ms = 2500  # 2.5 seconds into audio

        chunks_ending_near_silence = 0
        for chunk in adaptive_chunks:
            chunk_start_ms = chunk.timestamp / 1000
            chunk_audio = np.frombuffer(chunk.data, dtype=np.int16)
            chunk_duration_ms = len(chunk_audio) / 16
            chunk_end_ms = chunk_start_ms + chunk_duration_ms

            # Check if chunk ends within the silence region or shortly after
            if silence_start_ms <= chunk_end_ms <= silence_end_ms + 300:  # 300ms tolerance
                chunks_ending_near_silence += 1

        assert chunks_ending_near_silence >= 1, "At least one chunk should end near the silence gap"

    @pytest.mark.asyncio
    async def test_adaptive_chunking_maintains_temporal_continuity(self, real_audio_context, whisper_test_config):
        """Test that adaptive chunks maintain proper temporal continuity without gaps or overlaps."""

        from adaptive_chunker import AdaptiveChunker

        chunker = AdaptiveChunker(
            vad_model_path=whisper_test_config["vad_model_path"],
            target_chunk_duration_ms=1100,
            min_chunk_duration_ms=750,
            max_chunk_duration_ms=1800,
            vad_threshold=0.1,
            speech_boundary_tolerance_ms=200,
        )

        # Load real voice sample and take first 4 seconds
        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            # Downsample from 48kHz to 16kHz (every 3rd sample)
            audio_data = audio_48k[::3]

        # Skip initial silence and take 4 seconds of actual speech (starting from 1 second)
        speech_start_samples = 1 * 16000  # Skip first 1 second of silence
        speech_duration_samples = 4 * 16000  # Take 4 seconds of speech
        test_audio = audio_data[speech_start_samples : speech_start_samples + speech_duration_samples]
        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Process streaming chunks
        chunk_duration_ms = 75  # 75ms chunks
        chunk_samples = int(chunk_duration_ms * 16)

        adaptive_chunks = []
        for i in range(0, len(test_audio) - chunk_samples, chunk_samples):
            chunk_data = test_audio[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"continuity_test_{i // chunk_samples}",
            )

            result_chunks = await chunker.process_chunk(chunk)
            adaptive_chunks.extend(result_chunks)

        final_chunks = await chunker.finalize()
        adaptive_chunks.extend(final_chunks)

        # Verify temporal continuity
        assert len(adaptive_chunks) >= 2, "Should create multiple chunks for continuity testing"

        # Sort chunks by timestamp to ensure proper order
        adaptive_chunks.sort(key=lambda c: c.timestamp)

        # Check for gaps or overlaps between consecutive chunks
        for i in range(len(adaptive_chunks) - 1):
            current_chunk = adaptive_chunks[i]
            next_chunk = adaptive_chunks[i + 1]

            current_start_ms = current_chunk.timestamp / 1000
            current_audio = np.frombuffer(current_chunk.data, dtype=np.int16)
            current_duration_ms = len(current_audio) / 16
            current_end_ms = current_start_ms + current_duration_ms

            next_start_ms = next_chunk.timestamp / 1000

            # Check for gaps (small gaps are acceptable for speech-aligned chunking)
            gap_ms = next_start_ms - current_end_ms
            # Allow larger gaps for speech-aligned chunking since boundaries are optimized for speech
            max_acceptable_gap = 100  # 100ms maximum gap for speech boundaries
            assert gap_ms <= max_acceptable_gap, (
                f"Gap between chunk {i} and {i + 1}: {gap_ms}ms (should be ≤{max_acceptable_gap}ms)"
            )

            # Check for overlaps (small overlaps are less problematic than gaps)
            if gap_ms < 0:  # Negative gap means overlap
                overlap_ms = abs(gap_ms)
                max_acceptable_overlap = 50  # 50ms maximum overlap
                assert overlap_ms <= max_acceptable_overlap, (
                    f"Overlap between chunk {i} and {i + 1}: {overlap_ms}ms (should be ≤{max_acceptable_overlap}ms)"
                )

        # Verify total duration coverage
        first_chunk_start = adaptive_chunks[0].timestamp / 1000
        last_chunk = adaptive_chunks[-1]
        last_chunk_start = last_chunk.timestamp / 1000
        last_chunk_audio = np.frombuffer(last_chunk.data, dtype=np.int16)
        last_chunk_duration = len(last_chunk_audio) / 16
        last_chunk_end = last_chunk_start + last_chunk_duration

        total_coverage = last_chunk_end - first_chunk_start
        expected_duration = len(test_audio) / 16

        coverage_ratio = total_coverage / expected_duration
        assert 0.95 <= coverage_ratio <= 1.05, f"Coverage ratio should be ~1.0, got {coverage_ratio:.3f}"

    @pytest.mark.asyncio
    async def test_adaptive_chunking_performance_with_real_time_constraints(
        self, real_audio_context, whisper_test_config
    ):
        """Test that adaptive chunking meets real-time performance requirements."""

        import time

        from adaptive_chunker import AdaptiveChunker

        chunker = AdaptiveChunker(
            vad_model_path=whisper_test_config["vad_model_path"],
            target_chunk_duration_ms=1300,
            min_chunk_duration_ms=800,
            max_chunk_duration_ms=2000,
            vad_threshold=0.1,
            speech_boundary_tolerance_ms=250,
        )

        # Load real voice sample for realistic performance testing
        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"

        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            # Downsample from 48kHz to 16kHz (every 3rd sample)
            audio_data = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Test with real-time streaming chunks (50ms each)
        chunk_duration_ms = 50
        chunk_samples = int(chunk_duration_ms * 16)

        processing_times = []
        chunk_processing_times = []

        for i in range(0, min(len(audio_data), chunk_samples * 20), chunk_samples):
            chunk_data = audio_data[i : i + chunk_samples]
            if len(chunk_data) < chunk_samples:
                break

            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"perf_test_{i // chunk_samples}",
            )

            # Measure processing time for each chunk
            start_time = time.perf_counter()
            result_chunks = await chunker.process_chunk(chunk)
            end_time = time.perf_counter()

            chunk_processing_time = end_time - start_time
            chunk_processing_times.append(chunk_processing_time)

            # Measure finalization time when chunks are produced
            if result_chunks:
                for _ in result_chunks:
                    processing_times.append(chunk_processing_time)

        # Verify real-time performance requirements
        avg_chunk_processing_time = sum(chunk_processing_times) / len(chunk_processing_times)
        max_chunk_processing_time = max(chunk_processing_times)

        # Should process 50ms chunk in much less than 50ms (real-time requirement)
        assert avg_chunk_processing_time < 0.025, (
            f"Average processing time should be <25ms, got {avg_chunk_processing_time * 1000:.1f}ms"
        )

        assert max_chunk_processing_time < 0.040, (
            f"Max processing time should be <40ms, got {max_chunk_processing_time * 1000:.1f}ms"
        )

        # Verify consistent performance
        time_std = np.std(chunk_processing_times)
        assert time_std < 0.015, f"Processing time should be consistent (std <15ms), got {time_std * 1000:.1f}ms"

    @pytest.mark.asyncio
    async def test_adaptive_chunking_integrates_with_sliding_window(self, real_audio_context, whisper_test_config):
        """Test that adaptive chunking works seamlessly with sliding window buffer."""

        from adaptive_chunker import AdaptiveChunker
        from sliding_window_buffer import SlidingWindowBuffer

        # Create adaptive chunker
        chunker = AdaptiveChunker(
            vad_model_path=whisper_test_config["vad_model_path"],
            target_chunk_duration_ms=1400,
            min_chunk_duration_ms=900,
            max_chunk_duration_ms=2200,
            vad_threshold=0.1,
            speech_boundary_tolerance_ms=200,
        )

        # Create sliding window buffer that works with adaptive chunks
        sliding_buffer = SlidingWindowBuffer(
            window_size_ms=1500,  # Slightly larger than adaptive target
            overlap_ms=250,
            sample_rate=16000,
            adaptive_input=True,  # Enable adaptive chunk input mode
        )

        # Load real voice sample
        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"

        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            # Downsample from 48kHz to 16kHz (every 3rd sample)
            audio_data = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Process through adaptive chunker first
        chunk_duration_ms = 60
        chunk_samples = int(chunk_duration_ms * 16)

        adaptive_chunks = []
        for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
            chunk_data = audio_data[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"integration_chunk_{i // chunk_samples}",
            )

            result_chunks = await chunker.process_chunk(chunk)
            adaptive_chunks.extend(result_chunks)

        final_chunks = await chunker.finalize()
        adaptive_chunks.extend(final_chunks)

        # Feed adaptive chunks to sliding window buffer
        for adaptive_chunk in adaptive_chunks:
            await sliding_buffer.add_chunk(adaptive_chunk)

        # Get sliding windows from adaptive input
        sliding_windows = sliding_buffer.get_processing_windows()

        # Verify integration works correctly
        assert len(sliding_windows) >= 1, "Should produce sliding windows from adaptive chunks"

        # Verify windows maintain speech-aware characteristics
        for window in sliding_windows:
            window_audio = np.frombuffer(window.audio_data, dtype=np.int16).astype(np.float32) / 32767.0

            # Windows should contain meaningful speech content
            window_energy = np.mean(np.abs(window_audio))
            # Use microphone-specific threshold for window content validation
            mic = get_current_microphone()
            window_threshold = mic.get_test_thresholds()["window_energy_threshold"]

            assert window_energy > window_threshold, (
                f"Sliding windows should contain meaningful audio content from adaptive input "
                f"(energy: {window_energy:.8f}, threshold: {window_threshold:.8f}) for {mic.get_microphone_info()}"
            )

        # Verify temporal consistency between adaptive chunks and sliding windows
        # The sliding window may start later due to buffering requirements
        first_adaptive_start = adaptive_chunks[0].timestamp / 1000
        first_window_start = sliding_windows[0].start_timestamp

        # For integration testing, verify that windows exist within the time range of adaptive chunks
        last_adaptive_chunk = adaptive_chunks[-1]
        last_adaptive_start = last_adaptive_chunk.timestamp / 1000
        last_adaptive_audio = np.frombuffer(last_adaptive_chunk.data, dtype=np.int16)
        last_adaptive_end = last_adaptive_start + (len(last_adaptive_audio) / 16)

        # Verify windows fall within the adaptive chunk timespan
        assert first_window_start >= first_adaptive_start, (
            f"First window starts before adaptive chunks: {first_window_start}ms < {first_adaptive_start}ms"
        )

        last_window_end = sliding_windows[-1].end_timestamp
        assert last_window_end <= last_adaptive_end + 1000, (  # Allow 1s tolerance
            f"Last window extends too far beyond adaptive chunks: {last_window_end}ms > {last_adaptive_end + 1000}ms"
        )


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
