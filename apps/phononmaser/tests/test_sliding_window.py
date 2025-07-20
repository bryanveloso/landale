"""TDD tests for sliding window with continuous real audio.

Tests sliding window buffer that maintains overlapping audio chunks
to prevent word boundary fragmentation during streaming transcription.
"""

import asyncio
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from audio_processor import AudioChunk, AudioFormat


class TestSlidingWindowBuffer:
    """Test sliding window buffer with continuous real audio processing."""

    @pytest.mark.asyncio
    async def test_sliding_window_maintains_overlap(self, real_audio_context, test_audio_files):
        """Test that sliding window maintains proper overlap between consecutive chunks."""
        # This test will FAIL initially because SlidingWindowBuffer doesn't exist yet

        from sliding_window_buffer import SlidingWindowBuffer

        buffer = SlidingWindowBuffer(
            window_size_ms=1500,  # 1.5 second windows
            overlap_ms=250,  # 250ms overlap (industry standard)
            sample_rate=16000,
        )

        real_audio_context.register_processor(buffer)

        # Load continuous speech for sliding window testing
        import wave

        with wave.open(str(test_audio_files["continuous_speech"]), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Simulate streaming chunks (100ms each)
        chunk_duration_ms = 100
        chunk_samples = int(chunk_duration_ms * 16)  # 1600 samples per chunk

        # Add streaming chunks to sliding window - simulate realistic streaming
        chunk_id = 0
        total_duration_needed = 5000  # 5 seconds to get multiple windows
        chunks_needed = total_duration_needed // chunk_duration_ms

        for chunk_idx in range(min(chunks_needed, len(audio_data) // chunk_samples)):
            start_sample = chunk_idx * chunk_samples
            end_sample = min(start_sample + chunk_samples, len(audio_data))
            chunk_data = audio_data[start_sample:end_sample]
            timestamp_ms = chunk_id * chunk_duration_ms  # Sequential timing

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,  # Convert to microseconds
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"streaming_chunk_{chunk_id}",
            )

            await buffer.add_chunk(chunk)
            chunk_id += 1

            # Force window generation after every few chunks (simulate processing intervals)
            if chunk_id % 5 == 0:  # Every 500ms worth of data
                await buffer._generate_windows()

        # Get sliding windows for processing
        windows = buffer.get_processing_windows()

        # Debug buffer state
        buffer_info = buffer.get_buffer_info()
        print(f"Buffer info: {buffer_info}")
        print(f"Generated {len(windows)} windows")

        # Debug window timestamps
        for i, window in enumerate(windows[:5]):  # Show first 5 windows
            print(f"Window {i}: {window.start_timestamp}-{window.end_timestamp}ms")

        # Verify sliding window properties
        assert len(windows) >= 3, (
            f"Should generate multiple overlapping windows, got {len(windows)}. Buffer info: {buffer_info}"
        )

        # Check that consecutive windows have proper overlap
        for i in range(len(windows) - 1):
            window1 = windows[i]
            window2 = windows[i + 1]

            # Verify step size between windows (should be window_size - overlap = 1250ms)
            step_size = window2.start_timestamp - window1.start_timestamp

            assert 1200 <= step_size <= 1300, f"Window {i} step size should be ~1250ms, got {step_size}ms"

            # Verify overlap by checking that window1 end overlaps with window2 start
            window1_end = window1.start_timestamp + 1500
            window2_start = window2.start_timestamp

            # Overlap duration = how much window1 extends into window2's time
            actual_overlap = window1_end - window2_start

            assert 200 <= actual_overlap <= 300, f"Window {i} overlap should be ~250ms, got {actual_overlap}ms"

            # Verify audio data overlap
            window1_samples = len(window1.audio_data) // 2  # Convert bytes to samples
            window2_samples = len(window2.audio_data) // 2

            expected_window_samples = int(1.5 * 16000)  # 1.5s at 16kHz
            assert abs(window1_samples - expected_window_samples) < 1600, "Window should be ~1.5 seconds"
            assert abs(window2_samples - expected_window_samples) < 1600, "Window should be ~1.5 seconds"

    @pytest.mark.asyncio
    async def test_sliding_window_audio_continuity(self, real_audio_context, real_audio_generator):
        """Test that sliding window preserves audio continuity across boundaries."""

        from sliding_window_buffer import SlidingWindowBuffer

        buffer = SlidingWindowBuffer(
            window_size_ms=1000,  # 1 second windows
            overlap_ms=200,  # 200ms overlap
            sample_rate=16000,
        )

        # Generate continuous test audio
        continuous_audio = real_audio_generator.generate_speech_pattern(5.0)  # 5 seconds

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Add audio in small streaming chunks
        chunk_size_ms = 50  # 50ms chunks
        chunk_samples = int(chunk_size_ms * 16)

        for i in range(0, len(continuous_audio) - chunk_samples, chunk_samples):
            chunk_data = continuous_audio[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,  # microseconds
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"continuity_chunk_{i // chunk_samples}",
            )

            await buffer.add_chunk(chunk)

        # Get processed windows
        windows = buffer.get_processing_windows()

        assert len(windows) >= 3, "Should generate multiple windows from 5 seconds of audio"

        # Verify audio continuity in overlapping regions
        for i in range(len(windows) - 1):
            window1 = windows[i]
            window2 = windows[i + 1]

            # Extract overlap region from both windows
            overlap_samples = int(0.2 * 16000)  # 200ms overlap

            # Convert audio data back to float arrays
            window1_audio = np.frombuffer(window1.audio_data, dtype=np.int16).astype(np.float32) / 32767.0
            window2_audio = np.frombuffer(window2.audio_data, dtype=np.int16).astype(np.float32) / 32767.0

            # Get overlapping regions
            window1_end = window1_audio[-overlap_samples:]
            window2_start = window2_audio[:overlap_samples]

            # Verify audio data is similar in overlap region (allowing for quantization differences)
            correlation = np.corrcoef(window1_end, window2_start)[0, 1]
            assert correlation > 0.95, f"Overlap region correlation should be >0.95, got {correlation}"

    @pytest.mark.asyncio
    async def test_sliding_window_memory_management(self, real_audio_context, real_audio_generator):
        """Test that sliding window buffer manages memory efficiently with long streams."""

        from sliding_window_buffer import SlidingWindowBuffer

        buffer = SlidingWindowBuffer(
            window_size_ms=800,  # 800ms windows
            overlap_ms=150,  # 150ms overlap
            sample_rate=16000,
            max_windows=5,  # Limit memory usage
        )

        # Generate longer audio stream
        long_audio = real_audio_generator.generate_speech_pattern(10.0)  # 10 seconds

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Track memory usage during processing

        # Add audio in streaming fashion
        chunk_size_ms = 80  # 80ms chunks
        chunk_samples = int(chunk_size_ms * 16)

        for i in range(0, len(long_audio) - chunk_samples, chunk_samples):
            chunk_data = long_audio[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"memory_chunk_{i // chunk_samples}",
            )

            await buffer.add_chunk(chunk)

            # Check memory management
            current_windows = len(buffer.get_processing_windows())

            # Should not exceed max_windows limit
            assert current_windows <= 5, f"Should not exceed 5 windows, got {current_windows}"

            # Should start producing windows after enough data
            if i > chunk_samples * 15:  # After ~1.2 seconds
                assert current_windows >= 1, "Should have produced windows by now"

        # Verify final state
        final_windows = buffer.get_processing_windows()
        assert len(final_windows) <= 5, "Should maintain memory limit"
        assert len(final_windows) >= 3, "Should have meaningful number of windows"

    @pytest.mark.asyncio
    async def test_sliding_window_handles_silence_gaps(self, real_audio_context, test_audio_files):
        """Test sliding window behavior with silence gaps in audio stream."""

        from sliding_window_buffer import SlidingWindowBuffer

        buffer = SlidingWindowBuffer(
            window_size_ms=1200,  # 1.2 second windows
            overlap_ms=300,  # 300ms overlap
            sample_rate=16000,
            silence_threshold=0.01,  # Detect silence below 1% amplitude
        )

        # Load audio with gaps for testing
        import wave

        with wave.open(str(test_audio_files["speech_with_gaps"]), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Add audio with gaps in streaming chunks
        chunk_size_ms = 60  # 60ms chunks
        chunk_samples = int(chunk_size_ms * 16)

        for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
            chunk_data = audio_data[i : i + chunk_samples]
            timestamp_ms = int(i / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"gap_chunk_{i // chunk_samples}",
            )

            await buffer.add_chunk(chunk)

        # Get windows and analyze silence handling
        windows = buffer.get_processing_windows()

        assert len(windows) >= 2, "Should produce windows despite silence gaps"

        # Verify that windows contain meaningful audio content
        meaningful_windows = 0
        for window in windows:
            window_audio = np.frombuffer(window.audio_data, dtype=np.int16).astype(np.float32) / 32767.0
            max_amplitude = np.max(np.abs(window_audio))

            if max_amplitude > 0.05:  # 5% amplitude threshold for meaningful content
                meaningful_windows += 1

        assert meaningful_windows >= 1, "Should have at least one window with meaningful audio content"

    @pytest.mark.asyncio
    async def test_sliding_window_timing_accuracy(self, real_audio_context, real_audio_generator):
        """Test that sliding window maintains accurate timing across processing."""

        from sliding_window_buffer import SlidingWindowBuffer

        buffer = SlidingWindowBuffer(
            window_size_ms=1000,  # 1 second windows
            overlap_ms=250,  # 250ms overlap
            sample_rate=16000,
        )

        # Generate test audio with known timing
        test_audio = real_audio_generator.generate_speech_pattern(4.0)  # 4 seconds

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Add audio with precise timing
        chunk_size_ms = 100  # 100ms chunks
        chunk_samples = int(chunk_size_ms * 16)

        expected_timestamps = []

        for i in range(0, len(test_audio) - chunk_samples, chunk_samples):
            chunk_data = test_audio[i : i + chunk_samples]
            timestamp_ms = int(i / 16)
            expected_timestamps.append(timestamp_ms)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,  # microseconds
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"timing_chunk_{i // chunk_samples}",
            )

            await buffer.add_chunk(chunk)

        # Verify window timing accuracy
        windows = buffer.get_processing_windows()

        # First window should start at or near the beginning
        first_window = windows[0]
        assert first_window.start_timestamp <= 1000, "First window should start within first second"

        # Consecutive windows should maintain proper timing relationships
        for i in range(len(windows) - 1):
            window1 = windows[i]
            window2 = windows[i + 1]

            # Calculate expected timing
            step_size_ms = 1000 - 250  # window_size - overlap = 750ms steps
            expected_gap = step_size_ms
            actual_gap = window2.start_timestamp - window1.start_timestamp

            # Allow for small timing variations due to chunk boundaries
            assert abs(actual_gap - expected_gap) <= 100, f"Timing gap should be ~{expected_gap}ms, got {actual_gap}ms"

    @pytest.mark.asyncio
    async def test_sliding_window_handles_variable_chunk_sizes(self, real_audio_context, real_audio_generator):
        """Test sliding window with variable input chunk sizes (realistic streaming scenario)."""

        from sliding_window_buffer import SlidingWindowBuffer

        buffer = SlidingWindowBuffer(
            window_size_ms=1500,  # 1.5 second windows
            overlap_ms=300,  # 300ms overlap
            sample_rate=16000,
        )

        # Generate test audio
        test_audio = real_audio_generator.generate_speech_pattern(6.0)  # 6 seconds

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Add audio with variable chunk sizes (realistic streaming)
        current_position = 0
        chunk_id = 0

        # Variable chunk sizes: 50ms, 75ms, 120ms, 90ms, etc.
        chunk_sizes_ms = [50, 75, 120, 90, 60, 100, 80, 110, 70, 95]

        while current_position < len(test_audio) - 1600:  # Leave buffer for last chunk
            chunk_size_ms = chunk_sizes_ms[chunk_id % len(chunk_sizes_ms)]
            chunk_samples = int(chunk_size_ms * 16)

            # Ensure we don't exceed audio bounds
            chunk_samples = min(chunk_samples, len(test_audio) - current_position)

            chunk_data = test_audio[current_position : current_position + chunk_samples]
            timestamp_ms = int(current_position / 16)

            chunk = AudioChunk(
                timestamp=timestamp_ms * 1000,
                format=test_format,
                data=(chunk_data * 32767).astype(np.int16).tobytes(),
                source_id=f"variable_chunk_{chunk_id}",
            )

            await buffer.add_chunk(chunk)

            current_position += chunk_samples
            chunk_id += 1

        # Verify sliding window handles variable input correctly
        windows = buffer.get_processing_windows()

        assert len(windows) >= 3, "Should produce multiple windows despite variable chunk sizes"

        # Verify each window has correct duration
        for i, window in enumerate(windows):
            window_audio = np.frombuffer(window.audio_data, dtype=np.int16)
            window_duration_ms = len(window_audio) / 16  # Convert samples to ms

            # Should be close to 1500ms (allowing for boundary effects)
            assert 1400 <= window_duration_ms <= 1600, (
                f"Window {i} duration should be ~1500ms, got {window_duration_ms}ms"
            )

    @pytest.mark.asyncio
    async def test_sliding_window_concurrent_access(self, real_audio_context, real_audio_generator):
        """Test sliding window thread safety with concurrent chunk additions and window retrieval."""

        from sliding_window_buffer import SlidingWindowBuffer

        buffer = SlidingWindowBuffer(
            window_size_ms=1000,
            overlap_ms=200,
            sample_rate=16000,
        )

        # Generate test audio
        test_audio = real_audio_generator.generate_speech_pattern(3.0)

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Concurrent chunk addition
        async def add_chunks_task():
            chunk_size_ms = 80
            chunk_samples = int(chunk_size_ms * 16)

            for i in range(0, len(test_audio) - chunk_samples, chunk_samples):
                chunk_data = test_audio[i : i + chunk_samples]
                timestamp_ms = int(i / 16)

                chunk = AudioChunk(
                    timestamp=timestamp_ms * 1000,
                    format=test_format,
                    data=(chunk_data * 32767).astype(np.int16).tobytes(),
                    source_id=f"concurrent_chunk_{i // chunk_samples}",
                )

                await buffer.add_chunk(chunk)
                await asyncio.sleep(0.001)  # Small delay to encourage race conditions

        # Concurrent window retrieval
        async def get_windows_task():
            window_counts = []
            for _ in range(50):  # 50 attempts to get windows
                windows = buffer.get_processing_windows()
                window_counts.append(len(windows))
                await asyncio.sleep(0.002)  # Check windows frequently
            return window_counts

        # Run tasks concurrently
        add_task = asyncio.create_task(add_chunks_task())
        get_task = asyncio.create_task(get_windows_task())

        # Execute concurrently
        _, window_counts = await asyncio.gather(add_task, get_task)

        # Verify concurrent access worked without corruption
        assert max(window_counts) >= 1, "Should have produced windows during concurrent access"

        # Final state should be consistent
        final_windows = buffer.get_processing_windows()
        assert len(final_windows) >= 1, "Should have windows after concurrent operations"

        # Verify window integrity
        for window in final_windows:
            assert len(window.audio_data) > 0, "Windows should have audio data"
            assert window.start_timestamp >= 0, "Window timestamps should be valid"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
