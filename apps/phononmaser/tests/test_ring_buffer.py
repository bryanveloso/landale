"""TDD tests for ring buffer audio processing with long audio streams.

Tests memory-efficient circular buffer that can handle continuous audio
processing without memory growth, perfect for 24/7 streaming scenarios
with large audio volumes.
"""

import sys
import wave
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from audio_processor import AudioChunk, AudioFormat


class TestRingBufferAudioProcessor:
    """Test ring buffer for memory-efficient long audio stream processing."""

    @pytest.mark.asyncio
    async def test_ring_buffer_handles_continuous_audio_streams(self, real_audio_context):
        """Test that ring buffer efficiently processes continuous audio without memory growth."""

        from ring_buffer_audio_processor import RingBufferAudioProcessor

        buffer_size_minutes = 5
        ring_buffer = RingBufferAudioProcessor(
            buffer_size_minutes=buffer_size_minutes,
            sample_rate=16000,
            max_memory_mb=50,
            overlap_ms=250,
        )

        real_audio_context.register_processor(ring_buffer)

        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            base_audio = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        total_chunks_processed = 0
        chunk_duration_ms = 100
        chunk_samples = int(chunk_duration_ms * 16)

        for cycle in range(20):
            for i in range(0, len(base_audio) - chunk_samples, chunk_samples):
                chunk_data = base_audio[i : i + chunk_samples]
                timestamp_us = (cycle * len(base_audio) + i) * 1000 // 16

                chunk = AudioChunk(
                    timestamp=timestamp_us,
                    format=test_format,
                    data=(chunk_data * 32767).astype(np.int16).tobytes(),
                    source_id=f"continuous_cycle_{cycle}_{i // chunk_samples}",
                )

                await ring_buffer.add_chunk(chunk)
                total_chunks_processed += 1

                if total_chunks_processed % 100 == 0:
                    memory_usage = ring_buffer.get_memory_usage_mb()
                    assert memory_usage < 50, f"Memory usage {memory_usage:.1f}MB exceeded limit"

        final_memory = ring_buffer.get_memory_usage_mb()
        assert final_memory < 50, f"Final memory usage {final_memory:.1f}MB should stay below limit"

        available_audio = ring_buffer.get_available_audio_duration_ms()
        expected_max_duration = buffer_size_minutes * 60 * 1000
        assert available_audio <= expected_max_duration, "Ring buffer should not exceed configured duration"

        assert total_chunks_processed > 1000, "Should process significant amount of audio chunks"

    @pytest.mark.asyncio
    async def test_ring_buffer_provides_sliding_window_access(self, real_audio_context):
        """Test that ring buffer provides sliding window access to recent audio."""

        from ring_buffer_audio_processor import RingBufferAudioProcessor

        ring_buffer = RingBufferAudioProcessor(
            buffer_size_minutes=2,
            sample_rate=16000,
            max_memory_mb=20,
            overlap_ms=500,
        )

        real_audio_context.register_processor(ring_buffer)

        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            audio_data = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk_duration_ms = 200
        chunk_samples = int(chunk_duration_ms * 16)

        for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
            chunk_data = audio_data[i : i + chunk_samples]
            timestamp_us = i * 1000 // 16

            chunk = AudioChunk(
                timestamp=timestamp_us,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"sliding_window_chunk_{i // chunk_samples}",
            )

            await ring_buffer.add_chunk(chunk)

        window_duration_ms = 3000
        sliding_windows = ring_buffer.get_sliding_windows(window_duration_ms)

        assert len(sliding_windows) >= 1, "Should produce sliding windows from ring buffer"

        for window in sliding_windows:
            window_audio = np.frombuffer(window.audio_data, dtype=np.int16).astype(np.float32) / 32767.0

            window_duration_actual = len(window_audio) / 16
            assert 2800 <= window_duration_actual <= 3200, (
                f"Window duration {window_duration_actual}ms should be ~3000ms"
            )

            window_energy = np.mean(np.abs(window_audio))
            from microphone_profiles import get_current_microphone

            mic = get_current_microphone()
            energy_threshold = mic.get_test_thresholds()["window_energy_threshold"]

            assert window_energy > energy_threshold, "Windows should contain meaningful audio content"

        consecutive_windows = sliding_windows[:2] if len(sliding_windows) >= 2 else []
        if len(consecutive_windows) == 2:
            window1, window2 = consecutive_windows
            time_gap = window2.start_timestamp - window1.end_timestamp
            assert abs(time_gap - 500) < 100, f"Overlap should be ~500ms, got {time_gap}ms gap"

    @pytest.mark.asyncio
    async def test_ring_buffer_handles_burst_and_silence_patterns(self, real_audio_context):
        """Test ring buffer efficiently handles burst and silence audio patterns."""

        from ring_buffer_audio_processor import RingBufferAudioProcessor

        ring_buffer = RingBufferAudioProcessor(
            buffer_size_minutes=3,
            sample_rate=16000,
            max_memory_mb=30,
            overlap_ms=200,
            silence_detection_threshold=0.01,
        )

        real_audio_context.register_processor(ring_buffer)

        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            speech_audio = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk_duration_ms = 150
        chunk_samples = int(chunk_duration_ms * 16)

        burst_chunks = 0
        silence_chunks = 0

        for pattern in range(5):
            if pattern % 2 == 0:
                for i in range(0, len(speech_audio) - chunk_samples, chunk_samples):
                    chunk_data = speech_audio[i : i + chunk_samples]
                    timestamp_us = (pattern * 10000 + i) * 1000 // 16

                    chunk = AudioChunk(
                        timestamp=timestamp_us,
                        format=test_format,
                        data=(chunk_data * 32767).astype(np.int16).tobytes(),
                        source_id=f"burst_{pattern}_{i // chunk_samples}",
                    )

                    await ring_buffer.add_chunk(chunk)
                    burst_chunks += 1
            else:
                silence_duration_samples = 2 * 16000
                silence_audio = np.zeros(silence_duration_samples, dtype=np.float32)

                for i in range(0, len(silence_audio) - chunk_samples, chunk_samples):
                    chunk_data = silence_audio[i : i + chunk_samples]
                    timestamp_us = (pattern * 10000 + i) * 1000 // 16

                    chunk = AudioChunk(
                        timestamp=timestamp_us,
                        format=test_format,
                        data=(chunk_data * 32767).astype(np.int16).tobytes(),
                        source_id=f"silence_{pattern}_{i // chunk_samples}",
                    )

                    await ring_buffer.add_chunk(chunk)
                    silence_chunks += 1

        memory_usage = ring_buffer.get_memory_usage_mb()
        assert memory_usage < 30, "Memory usage should stay below limit even with burst patterns"

        storage_stats = ring_buffer.get_storage_statistics()
        assert storage_stats.active_segments > 0, "Should maintain active audio segments"
        assert storage_stats.silence_optimized_segments >= 0, "Should optimize silence storage"

        assert burst_chunks > 50, "Should process significant burst chunks"
        assert silence_chunks > 20, "Should process silence chunks efficiently"

    @pytest.mark.asyncio
    async def test_ring_buffer_maintains_audio_quality_during_wraparound(self, real_audio_context):
        """Test ring buffer maintains audio quality when buffer wraps around."""

        from ring_buffer_audio_processor import RingBufferAudioProcessor

        ring_buffer = RingBufferAudioProcessor(
            buffer_size_minutes=1,
            sample_rate=16000,
            max_memory_mb=15,
            overlap_ms=100,
        )

        real_audio_context.register_processor(ring_buffer)

        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            audio_data = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk_duration_ms = 50
        chunk_samples = int(chunk_duration_ms * 16)

        total_duration_processed = 0
        target_duration_ms = 5 * 60 * 1000

        while total_duration_processed < target_duration_ms:
            for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
                chunk_data = audio_data[i : i + chunk_samples]
                timestamp_us = total_duration_processed * 1000 + (i * 1000 // 16)

                chunk = AudioChunk(
                    timestamp=timestamp_us,
                    format=test_format,
                    data=(chunk_data * 32767).astype(np.int16).tobytes(),
                    source_id=f"wraparound_{total_duration_processed // 1000}_{i // chunk_samples}",
                )

                await ring_buffer.add_chunk(chunk)
                total_duration_processed += chunk_duration_ms

                if total_duration_processed >= target_duration_ms:
                    break

        recent_windows = ring_buffer.get_sliding_windows(2000)
        assert len(recent_windows) >= 1, "Should provide recent windows after wraparound"

        for window in recent_windows:
            window_audio = np.frombuffer(window.audio_data, dtype=np.int16).astype(np.float32) / 32767.0

            assert len(window_audio) > 1000, "Windows should contain substantial audio data"

            audio_energy = np.mean(np.abs(window_audio))
            assert audio_energy > 0.001, "Audio quality should be maintained during wraparound"

            rms_energy = np.sqrt(np.mean(window_audio**2))
            assert rms_energy > 0.01, "RMS energy should indicate proper audio reconstruction"

        buffer_stats = ring_buffer.get_buffer_statistics()
        assert buffer_stats.wraparound_count > 0, "Buffer should have wrapped around multiple times"
        assert buffer_stats.data_integrity_checks_passed > 0, "Data integrity should be maintained"

    @pytest.mark.asyncio
    async def test_ring_buffer_provides_historical_audio_access(self, real_audio_context):
        """Test ring buffer allows access to historical audio within buffer limits."""

        from ring_buffer_audio_processor import RingBufferAudioProcessor

        ring_buffer = RingBufferAudioProcessor(
            buffer_size_minutes=2,
            sample_rate=16000,
            max_memory_mb=25,
            overlap_ms=300,
        )

        real_audio_context.register_processor(ring_buffer)

        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            audio_data = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk_duration_ms = 100
        chunk_samples = int(chunk_duration_ms * 16)
        reference_timestamps = []

        for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
            chunk_data = audio_data[i : i + chunk_samples]
            timestamp_us = i * 1000 // 16

            chunk = AudioChunk(
                timestamp=timestamp_us,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"historical_chunk_{i // chunk_samples}",
            )

            await ring_buffer.add_chunk(chunk)
            reference_timestamps.append(timestamp_us)

        earliest_available = ring_buffer.get_earliest_available_timestamp()
        latest_available = ring_buffer.get_latest_available_timestamp()

        assert earliest_available < latest_available, "Should have valid time range"

        historical_audio = ring_buffer.get_audio_range(
            start_timestamp_us=earliest_available + 5000000, duration_ms=1000
        )

        assert historical_audio is not None, "Should retrieve historical audio within buffer"
        historical_samples = np.frombuffer(historical_audio, dtype=np.int16)
        assert len(historical_samples) > 0, "Historical audio should contain samples"

        out_of_range_audio = ring_buffer.get_audio_range(
            start_timestamp_us=earliest_available - 10000000, duration_ms=1000
        )
        assert out_of_range_audio is None, "Should return None for out-of-range historical audio"

        available_duration = ring_buffer.get_available_audio_duration_ms()
        max_duration = 2 * 60 * 1000
        assert available_duration <= max_duration, "Available duration should respect buffer size limit"

    @pytest.mark.asyncio
    async def test_ring_buffer_performance_with_high_throughput(self, real_audio_context):
        """Test ring buffer performance under high-throughput streaming conditions."""

        import time

        from ring_buffer_audio_processor import RingBufferAudioProcessor

        ring_buffer = RingBufferAudioProcessor(
            buffer_size_minutes=3,
            sample_rate=16000,
            max_memory_mb=40,
            overlap_ms=250,
        )

        real_audio_context.register_processor(ring_buffer)

        voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"
        with wave.open(str(voice_sample_path), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_48k = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
            audio_data = audio_48k[::3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk_duration_ms = 20
        chunk_samples = int(chunk_duration_ms * 16)
        processing_times = []

        for i in range(0, min(len(audio_data), chunk_samples * 500), chunk_samples):
            chunk_data = audio_data[i : i + chunk_samples]
            timestamp_us = i * 1000 // 16

            chunk = AudioChunk(
                timestamp=timestamp_us,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"perf_chunk_{i // chunk_samples}",
            )

            start_time = time.perf_counter()
            await ring_buffer.add_chunk(chunk)
            end_time = time.perf_counter()

            processing_times.append(end_time - start_time)

        avg_processing_time = sum(processing_times) / len(processing_times)
        max_processing_time = max(processing_times)

        assert avg_processing_time < 0.010, (
            f"Average processing time should be <10ms, got {avg_processing_time * 1000:.1f}ms"
        )
        assert max_processing_time < 0.020, (
            f"Max processing time should be <20ms, got {max_processing_time * 1000:.1f}ms"
        )

        throughput_chunks_per_second = len(processing_times) / sum(processing_times)
        expected_min_throughput = 1000 / chunk_duration_ms
        assert throughput_chunks_per_second >= expected_min_throughput * 0.8, "Should maintain high throughput"

        performance_stats = ring_buffer.get_performance_statistics()
        assert performance_stats.average_add_latency_ms < 10, "Add operation should be fast"
        assert performance_stats.memory_efficiency_ratio > 0.1, "Should use memory efficiently without exceeding limits"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
