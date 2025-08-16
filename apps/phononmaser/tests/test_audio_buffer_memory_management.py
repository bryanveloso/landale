"""P1 HIGH: Audio buffer memory management tests for Phononmaser.

These tests validate critical memory bounds and overflow scenarios to prevent
memory exhaustion in audio processing during production streaming sessions.

Focus areas:
- Buffer size limits and overflow protection
- Memory leak prevention during continuous operation
- Proper cleanup of audio resources
- Chunk count explosion prevention
- Memory usage tracking accuracy
"""

import asyncio
import gc
import time
from unittest.mock import patch

import numpy as np
import psutil
import pytest
import pytest_asyncio

from src.audio_processor import AudioChunk, AudioFormat, AudioProcessor
from src.events import TranscriptionEvent
from tests.fixtures.generate_test_audio import AudioTestDataGenerator

# Mark all tests as async
pytestmark = pytest.mark.asyncio


class TestAudioBufferMemoryBounds:
    """Test audio buffer memory bounds and protection mechanisms."""

    @pytest.fixture
    def audio_format(self):
        """Standard audio format for testing."""
        return AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

    @pytest.fixture
    def processor_config(self):
        """Audio processor configuration for testing."""
        return {
            "whisper_model_path": "/tmp/test_model.bin",
            "buffer_duration_ms": 1500,
            "max_buffer_size": 1024 * 1024,  # 1MB for testing
            "memory_optimization": False,
            "whisper_threads": 1,
        }

    @pytest_asyncio.fixture
    async def audio_processor(self, processor_config):
        """Create audio processor with mocked Whisper dependencies."""
        with patch("os.path.exists", return_value=True):
            processor = AudioProcessor(**processor_config)
            yield processor
            await processor.stop()

    @pytest.fixture
    def audio_generator(self):
        """Audio test data generator."""
        return AudioTestDataGenerator()

    def create_audio_chunk(self, audio_format, size_bytes=1024, timestamp=None):
        """Create an audio chunk with specified size."""
        if timestamp is None:
            timestamp = int(time.time() * 1_000_000)

        # Create dummy audio data of specified size
        data = b"\x00" * size_bytes

        return AudioChunk(timestamp=timestamp, format=audio_format, data=data, source_id="test_source")

    async def test_buffer_size_limit_enforcement(self, audio_processor, audio_format):
        """Test that buffer size limits are strictly enforced."""
        await audio_processor.start()

        # Add chunks that exceed buffer size limit
        chunk_size = 512 * 1024  # 512KB per chunk
        max_chunks = 3  # Should exceed 1MB limit

        for i in range(max_chunks):
            chunk = self.create_audio_chunk(
                audio_format,
                size_bytes=chunk_size,
                timestamp=i * 100_000,  # 100ms apart
            )
            audio_processor.add_chunk(chunk)

        # Buffer should not exceed max_buffer_size
        assert audio_processor.buffer.total_size <= audio_processor.max_buffer_size

        # Should have triggered overflow events
        assert audio_processor.buffer_overflow_events > 0

        # Buffer should contain fewer chunks than added
        assert len(audio_processor.buffer.chunks) < max_chunks

    async def test_chunk_count_explosion_prevention(self, audio_processor, audio_format):
        """Test prevention of chunk count explosion."""
        await audio_processor.start()

        # Add many small chunks that could explode chunk count
        small_chunk_size = 100  # Very small chunks
        chunk_count = 1500  # Exceeds max_chunk_count (1000)

        for i in range(chunk_count):
            chunk = self.create_audio_chunk(
                audio_format,
                size_bytes=small_chunk_size,
                timestamp=i * 1000,  # 1ms apart (very rapid)
            )
            audio_processor.add_chunk(chunk)

        # Should not exceed max_chunk_count
        assert len(audio_processor.buffer.chunks) <= audio_processor.max_chunk_count

        # Should have triggered overflow protection
        assert audio_processor.buffer_overflow_events > 0

    async def test_memory_usage_tracking_accuracy(self, audio_processor, audio_format):
        """Test that memory usage tracking accurately reflects actual usage."""
        await audio_processor.start()

        # Baseline memory stats
        initial_stats = audio_processor.get_memory_stats()
        initial_usage = audio_processor.get_memory_usage()

        # Add known amount of data
        test_data_size = 256 * 1024  # 256KB
        chunk = self.create_audio_chunk(audio_format, size_bytes=test_data_size)
        audio_processor.add_chunk(chunk)

        # Verify memory tracking accuracy
        final_stats = audio_processor.get_memory_stats()
        final_usage = audio_processor.get_memory_usage()

        # Buffer memory should increase by exactly the data size
        buffer_increase = final_stats["buffer_memory"] - initial_stats["buffer_memory"]
        assert buffer_increase == test_data_size

        # Total usage should increase by at least the data size
        usage_increase = final_usage - initial_usage
        assert usage_increase >= test_data_size

    async def test_memory_leak_during_continuous_operation(self, audio_processor, audio_format):
        """Test for memory leaks during continuous audio processing."""
        # Get initial memory baseline
        process = psutil.Process()
        initial_memory = process.memory_info().rss

        await audio_processor.start()

        # Mock transcription to prevent actual Whisper calls
        async def mock_transcription_callback(event):
            pass

        audio_processor.transcription_callback = mock_transcription_callback

        # Simulate continuous operation with buffer cycling
        operation_cycles = 50
        chunk_size = 32 * 1024  # 32KB chunks

        for cycle in range(operation_cycles):
            # Add chunks to trigger processing
            for i in range(5):
                chunk = self.create_audio_chunk(
                    audio_format, size_bytes=chunk_size, timestamp=(cycle * 5 + i) * 100_000
                )
                audio_processor.add_chunk(chunk)

            # Force buffer processing by manipulating internal state
            if audio_processor.buffer.chunks:
                # Simulate buffer processing without actual Whisper call
                with patch.object(audio_processor, "_process_buffer", return_value=None):
                    if audio_processor._should_process_buffer():
                        await audio_processor._process_buffer()

            # Periodic garbage collection to settle memory
            if cycle % 10 == 0:
                gc.collect()
                await asyncio.sleep(0.01)

        # Final garbage collection
        gc.collect()
        await asyncio.sleep(0.1)

        # Check memory usage
        final_memory = process.memory_info().rss
        memory_growth = final_memory - initial_memory

        # Allow reasonable growth but prevent unbounded leaks
        # 50MB growth limit for 50 cycles is conservative
        max_allowed_growth = 50 * 1024 * 1024  # 50MB
        assert memory_growth < max_allowed_growth, (
            f"Potential memory leak: {memory_growth / 1024 / 1024:.1f}MB growth during {operation_cycles} cycles"
        )

    async def test_buffer_overflow_frequency_tracking(self, audio_processor, audio_format):
        """Test tracking of buffer overflow frequency for monitoring."""
        await audio_processor.start()

        # Trigger multiple overflows by exceeding both size and count limits
        large_chunk_size = audio_processor.max_buffer_size // 2  # Half max size

        # Add chunks that will cause multiple overflows
        for i in range(5):
            chunk = self.create_audio_chunk(audio_format, size_bytes=large_chunk_size, timestamp=i * 100_000)
            audio_processor.add_chunk(chunk)

        # Should have tracked multiple overflow events
        assert audio_processor.buffer_overflow_events >= 2

        # Add more chunks to trigger warning threshold (every 10 overflows)
        for i in range(10):
            chunk = self.create_audio_chunk(audio_format, size_bytes=large_chunk_size, timestamp=(i + 10) * 100_000)
            audio_processor.add_chunk(chunk)

        # Should have hit warning threshold
        assert audio_processor.buffer_overflow_events >= 10

    async def test_memory_pressure_under_high_input_rate(self, audio_processor, audio_format):
        """Test memory behavior under high audio input rate."""
        await audio_processor.start()

        # Simulate high input rate (1ms chunks, much faster than processing)
        high_rate_chunk_size = 2048  # 2KB per chunk
        rapid_chunks = 500  # 500 chunks in rapid succession

        start_time = time.time()

        for i in range(rapid_chunks):
            chunk = self.create_audio_chunk(
                audio_format,
                size_bytes=high_rate_chunk_size,
                timestamp=i * 1000,  # 1ms apart
            )
            audio_processor.add_chunk(chunk)

            # No delay - simulate overwhelming input rate

        end_time = time.time()
        processing_time = end_time - start_time

        # Memory should remain bounded despite high input rate
        current_usage = audio_processor.get_memory_usage()

        # Should not exceed configured limits
        assert audio_processor.buffer.total_size <= audio_processor.max_buffer_size
        assert len(audio_processor.buffer.chunks) <= audio_processor.max_chunk_count

        # Should handle rapid input without excessive memory growth
        assert current_usage < audio_processor.max_buffer_size * 2  # 2x safety margin

        # Should complete processing in reasonable time (not hang)
        assert processing_time < 5.0  # 5 second limit

    async def test_buffer_cleanup_after_processing(self, audio_processor, audio_format):
        """Test proper buffer cleanup after audio processing."""
        await audio_processor.start()

        # Mock successful processing
        mock_event = TranscriptionEvent(timestamp=int(time.time() * 1_000_000), text="Test transcription", duration=1.5)

        with (
            patch.object(audio_processor, "_combine_chunks", return_value=b"test_data"),
            patch.object(audio_processor, "_pcm_to_float32", return_value=np.zeros(16000)),
            patch.object(audio_processor, "_parse_whisper_output", return_value=mock_event),
            patch("subprocess.run") as mock_subprocess,
        ):
            mock_subprocess.return_value.returncode = 0
            mock_subprocess.return_value.stdout = "Test output"

            # Add chunks to buffer
            for i in range(10):
                chunk = self.create_audio_chunk(
                    audio_format,
                    size_bytes=16384,
                    timestamp=i * 150_000,  # 150ms apart
                )
                audio_processor.add_chunk(chunk)

            # Force processing
            result = await audio_processor._process_buffer()

            # Buffer should be reset after processing
            assert len(audio_processor.buffer.chunks) == 0
            assert audio_processor.buffer.total_size == 0
            assert audio_processor.buffer.start_timestamp == 0
            assert audio_processor.buffer.end_timestamp == 0

            # Should have processed successfully
            assert result is not None
            assert result.text == "Test transcription"

    async def test_memory_stats_peak_tracking(self, audio_processor, audio_format):
        """Test that peak memory usage is tracked correctly."""
        await audio_processor.start()

        initial_stats = audio_processor.get_memory_stats()
        initial_peak = initial_stats["peak_memory"]

        # Add substantial amount of data
        large_chunk_size = 512 * 1024  # 512KB
        chunk = self.create_audio_chunk(audio_format, size_bytes=large_chunk_size)
        audio_processor.add_chunk(chunk)

        # Check peak tracking
        mid_stats = audio_processor.get_memory_stats()
        mid_peak = mid_stats["peak_memory"]

        # Peak should have increased
        assert mid_peak > initial_peak

        # Remove data (simulate processing)
        audio_processor.buffer.chunks.clear()
        audio_processor.buffer.total_size = 0

        # Peak should remain at maximum seen
        final_stats = audio_processor.get_memory_stats()
        final_peak = final_stats["peak_memory"]

        assert final_peak == mid_peak  # Peak should not decrease


class TestAudioBufferResourceCleanup:
    """Test proper cleanup of audio processing resources."""

    @pytest_asyncio.fixture
    async def processor_with_mocks(self):
        """Create processor with all external dependencies mocked."""
        with patch("os.path.exists", return_value=True):
            processor = AudioProcessor(
                whisper_model_path="/tmp/test_model.bin",
                buffer_duration_ms=500,  # Short for fast testing
                max_buffer_size=64 * 1024,  # 64KB for testing
                memory_optimization=False,
            )
            yield processor
            await processor.stop()

    async def test_temporary_file_cleanup_on_error(self, processor_with_mocks):
        """Test that temporary files are cleaned up even when processing fails."""
        await processor_with_mocks.start()

        # Mock file operations to track temp file creation/deletion
        temp_files_created = []
        temp_files_deleted = []

        original_named_temp_file = __import__("tempfile").NamedTemporaryFile

        def mock_named_temp_file(*args, **kwargs):
            temp_file = original_named_temp_file(*args, **kwargs)
            temp_files_created.append(temp_file.name)
            return temp_file

        def mock_unlink(path):
            temp_files_deleted.append(path)

        with (
            patch("tempfile.NamedTemporaryFile", side_effect=mock_named_temp_file),
            patch("os.unlink", side_effect=mock_unlink),
            patch("subprocess.run", side_effect=Exception("Whisper failed")),
        ):
            # Add chunks and trigger processing
            audio_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
            chunk = AudioChunk(
                timestamp=int(time.time() * 1_000_000),
                format=audio_format,
                data=b"\x00" * 16384,
                source_id="test",
            )
            processor_with_mocks.add_chunk(chunk)

            # Force processing that will fail
            import contextlib

            with contextlib.suppress(Exception):
                await processor_with_mocks._process_buffer()

            # Temporary files should still be cleaned up
            assert len(temp_files_created) == len(temp_files_deleted)
            for created_file in temp_files_created:
                assert created_file in temp_files_deleted

    async def test_memory_optimization_resource_cleanup(self, processor_with_mocks):
        """Test resource cleanup in memory optimization mode."""
        # Enable memory optimization
        processor_with_mocks.memory_optimization = True
        await processor_with_mocks.start()

        # Mock subprocess to avoid actual Whisper calls
        with patch("subprocess.run") as mock_subprocess:
            mock_subprocess.return_value.returncode = 0
            mock_subprocess.return_value.stdout = b"Test output"

            # Add chunk and process
            audio_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
            chunk = AudioChunk(
                timestamp=int(time.time() * 1_000_000), format=audio_format, data=b"\x00" * 32768, source_id="test"
            )
            processor_with_mocks.add_chunk(chunk)

            # Test that memory optimization uses in-memory processing
            # Process with memory optimization
            result = await processor_with_mocks._process_buffer()

            # Force garbage collection
            gc.collect()

            # Should have processed successfully
            assert result is not None

            # Buffer should be empty after processing
            assert len(processor_with_mocks.buffer.chunks) == 0
            assert processor_with_mocks.buffer.total_size == 0

    async def test_processor_stop_cleanup(self, processor_with_mocks):
        """Test that processor stop properly cleans up resources."""
        await processor_with_mocks.start()

        # Add some data to buffer
        audio_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        for i in range(5):
            chunk = AudioChunk(
                timestamp=int(time.time() * 1_000_000) + i * 100_000,
                format=audio_format,
                data=b"\x00" * 8192,
                source_id="test",
            )
            processor_with_mocks.add_chunk(chunk)

        # Verify buffer has data
        assert len(processor_with_mocks.buffer.chunks) > 0
        assert processor_with_mocks.buffer.total_size > 0
        assert processor_with_mocks.is_running is True

        # Stop processor
        await processor_with_mocks.stop()

        # Verify cleanup
        assert processor_with_mocks.is_running is False
        assert processor_with_mocks.process_task is None or processor_with_mocks.process_task.done()

    async def test_task_cancellation_on_stop(self, processor_with_mocks):
        """Test that background tasks are properly cancelled on stop."""
        await processor_with_mocks.start()

        # Verify processing task is running
        assert processor_with_mocks.process_task is not None
        assert not processor_with_mocks.process_task.done()

        # Stop processor
        await processor_with_mocks.stop()

        # Task should be cancelled or completed
        assert processor_with_mocks.process_task.done()


class TestAudioBufferStressScenarios:
    """Test audio buffer behavior under stress conditions."""

    @pytest_asyncio.fixture
    async def stress_processor(self):
        """Create processor configured for stress testing."""
        with patch("os.path.exists", return_value=True):
            processor = AudioProcessor(
                whisper_model_path="/tmp/test_model.bin",
                buffer_duration_ms=100,  # Very short for rapid processing
                max_buffer_size=32 * 1024,  # Small buffer for stress testing
                memory_optimization=True,  # Enable optimization
            )
            # Override chunk limit for stress testing
            processor.max_chunk_count = 50
            yield processor
            await processor.stop()

    async def test_concurrent_buffer_access(self, stress_processor):
        """Test buffer safety under concurrent access patterns."""
        await stress_processor.start()

        audio_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        async def add_chunks_rapidly():
            """Add chunks rapidly in background."""
            for i in range(100):
                chunk = AudioChunk(
                    timestamp=int(time.time() * 1_000_000) + i * 10_000,
                    format=audio_format,
                    data=b"\x00" * 1024,
                    source_id=f"concurrent_{i}",
                )
                stress_processor.add_chunk(chunk)
                await asyncio.sleep(0.001)  # 1ms between chunks

        async def check_memory_stats():
            """Check memory stats concurrently."""
            for _ in range(50):
                stats = stress_processor.get_memory_stats()
                usage = stress_processor.get_memory_usage()
                assert stats is not None
                assert usage >= 0
                await asyncio.sleep(0.002)  # 2ms between checks

        # Run concurrent operations
        tasks = [
            add_chunks_rapidly(),
            check_memory_stats(),
        ]

        await asyncio.gather(*tasks, return_exceptions=True)

        # System should remain stable
        assert stress_processor.is_running
        final_stats = stress_processor.get_memory_stats()
        assert final_stats["buffer_memory"] <= stress_processor.max_buffer_size

    async def test_buffer_thrashing_scenario(self, stress_processor):
        """Test buffer behavior under rapid overflow conditions."""
        await stress_processor.start()

        audio_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Create chunks that will cause constant thrashing
        thrash_chunk_size = stress_processor.max_buffer_size // 4  # 1/4 buffer size

        initial_overflow_count = stress_processor.buffer_overflow_events

        # Add many chunks rapidly to cause buffer thrashing
        for i in range(20):
            chunk = AudioChunk(
                timestamp=int(time.time() * 1_000_000) + i * 1000,
                format=audio_format,
                data=b"\x00" * thrash_chunk_size,
                source_id=f"thrash_{i}",
            )
            stress_processor.add_chunk(chunk)

        # Should have caused many overflows
        final_overflow_count = stress_processor.buffer_overflow_events
        assert final_overflow_count > initial_overflow_count

        # Buffer should still be within limits
        assert stress_processor.buffer.total_size <= stress_processor.max_buffer_size
        assert len(stress_processor.buffer.chunks) <= stress_processor.max_chunk_count

        # System should remain responsive
        memory_usage = stress_processor.get_memory_usage()
        assert memory_usage > 0  # Should respond to queries
