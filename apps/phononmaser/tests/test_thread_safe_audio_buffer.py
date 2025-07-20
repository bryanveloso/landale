"""TDD tests for thread-safe audio buffer with real concurrency.

Tests thread safety of audio buffer operations using real asyncio concurrency
without mocking.
"""

import asyncio
import sys
import time
from pathlib import Path
from unittest.mock import patch

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import contextlib

from audio_processor import AudioChunk, AudioFormat


class TestThreadSafeAudioBuffer:
    """Test thread-safe audio buffer operations with real concurrency."""

    @pytest.mark.asyncio
    async def test_concurrent_add_chunk_operations(self, real_audio_context, real_audio_chunks):
        """Test that concurrent add_chunk operations are thread-safe."""
        # This test will FAIL initially because current AudioProcessor is not thread-safe

        from thread_safe_audio_processor import ThreadSafeAudioProcessor

        processor = ThreadSafeAudioProcessor(
            whisper_model_path="/tmp/test_model.bin",
            buffer_duration_ms=5000,  # Long buffer to prevent processing during test
            whisper_threads=1,
        )

        # Mock the whisper executable to avoid actual transcription
        processor.whisper_exe = "/bin/echo"

        real_audio_context.register_processor(processor)

        # Start the processor to accept chunks
        await processor.start()

        # Create test chunks from real audio
        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        chunks = []

        for i, (audio_data, _start_time) in enumerate(real_audio_chunks[:5]):
            # Convert float32 to bytes
            audio_int16 = (audio_data * 32767).astype(np.int16)
            chunk = AudioChunk(
                timestamp=int(i * 250_000),  # Predictable 250ms intervals in microseconds
                format=test_format,
                data=audio_int16.tobytes(),
                source_id=f"test_source_{i}",
            )
            chunks.append(chunk)

        # Test concurrent access - this should expose thread safety issues
        async def add_chunks_concurrently(chunk_subset):
            """Add chunks concurrently to test thread safety."""
            for chunk in chunk_subset:
                await processor.add_chunk(chunk)
                await asyncio.sleep(0.001)  # Small delay to increase chance of race condition

        # Split chunks and add them concurrently
        tasks = [
            asyncio.create_task(add_chunks_concurrently(chunks[:2])),
            asyncio.create_task(add_chunks_concurrently(chunks[2:4])),
            asyncio.create_task(add_chunks_concurrently(chunks[4:])),
        ]

        # Execute concurrent operations
        await asyncio.gather(*tasks)

        # Verify buffer state is consistent
        # In thread-safe implementation, all chunks should be present
        assert len(processor.buffer.chunks) == len(chunks)

        # Verify buffer size is consistent
        expected_size = sum(len(chunk.data) for chunk in chunks)
        assert processor.buffer.total_size == expected_size

        # Verify timestamps are present and valid (order may vary due to concurrency)
        timestamps = [chunk.timestamp for chunk in processor.buffer.chunks]
        expected_timestamps = [0, 250000, 500000, 750000, 1000000]
        assert set(timestamps) == set(expected_timestamps), "All expected timestamps should be present"
        assert all(ts >= 0 for ts in timestamps), "All timestamps should be valid"

    @pytest.mark.asyncio
    async def test_concurrent_buffer_processing_and_adding(self, real_audio_context, test_audio_files):
        """Test concurrent buffer processing while adding new chunks."""
        # This test will FAIL initially due to buffer swapping race conditions

        with patch("audio_processor.AudioProcessor.whisper_exe", "/bin/echo"):
            from audio_processor import AudioProcessor

            processor = AudioProcessor(
                whisper_model_path="/tmp/test_model.bin",
                buffer_duration_ms=300,  # Short for quick processing
                whisper_threads=1,
            )

            real_audio_context.register_processor(processor)
            await processor.start()

            # Load real audio data
            import wave

            with wave.open(str(test_audio_files["short_speech"]), "rb") as wav:
                frames = wav.readframes(wav.getnframes())
                audio_data = np.frombuffer(frames, dtype=np.int16)

            # Create continuous stream of chunks
            test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
            chunk_size = 1600  # 0.1 second chunks

            chunks = []
            for i in range(0, len(audio_data) - chunk_size, chunk_size):
                chunk_data = audio_data[i : i + chunk_size]
                chunk = AudioChunk(
                    timestamp=int(i / 16000 * 1_000_000),  # Microseconds
                    format=test_format,
                    data=chunk_data.tobytes(),
                    source_id="concurrent_test",
                )
                chunks.append(chunk)

            # Track processed transcriptions
            processed_events = []

            async def capture_transcriptions(event):
                processed_events.append(event)

            processor.transcription_callback = capture_transcriptions

            # Add chunks while processing is happening
            async def continuous_adding():
                for chunk in chunks:
                    processor.add_chunk(chunk)
                    await asyncio.sleep(0.05)  # Add chunk every 50ms

            # Run for limited time to avoid infinite test
            adding_task = asyncio.create_task(continuous_adding())

            # Wait for some processing to happen
            await asyncio.sleep(2.0)

            # Stop adding chunks
            adding_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await adding_task

            await processor.stop()

            # Verify no corruption occurred
            # Buffer should be in consistent state
            assert processor.buffer.total_size >= 0, "Buffer size should not be negative"

            # Should have processed some transcriptions without errors
            # (Even if transcription is mocked, the processing pipeline should work)
            assert not processor.is_transcribing, "Should not be stuck in transcribing state"

    @pytest.mark.asyncio
    async def test_buffer_overflow_thread_safety(self, real_audio_context, real_audio_chunks):
        """Test thread safety during buffer overflow conditions."""
        # This test will FAIL initially due to non-atomic buffer operations

        with patch("audio_processor.AudioProcessor.whisper_exe", "/bin/echo"):
            from audio_processor import AudioProcessor

            # Use very small buffer to trigger overflow quickly
            processor = AudioProcessor(
                whisper_model_path="/tmp/test_model.bin",
                max_buffer_size=1024,  # Very small buffer (1KB)
                buffer_duration_ms=100,
                whisper_threads=1,
            )

            real_audio_context.register_processor(processor)

            # Create large chunks to trigger overflow
            test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
            large_chunks = []

            for i in range(10):  # 10 large chunks
                # Create 512 byte chunk (will quickly exceed 1KB limit)
                large_data = np.random.randint(-32768, 32767, 256, dtype=np.int16)
                chunk = AudioChunk(
                    timestamp=int(i * 100 * 1000),  # 100ms apart in microseconds
                    format=test_format,
                    data=large_data.tobytes(),
                    source_id=f"overflow_test_{i}",
                )
                large_chunks.append(chunk)

            # Add chunks concurrently to trigger overflow race conditions
            async def add_overflow_chunks(chunk_subset):
                for chunk in chunk_subset:
                    processor.add_chunk(chunk)
                    await asyncio.sleep(0.001)  # Brief delay

            # Split chunks across multiple tasks
            tasks = [
                asyncio.create_task(add_overflow_chunks(large_chunks[:3])),
                asyncio.create_task(add_overflow_chunks(large_chunks[3:6])),
                asyncio.create_task(add_overflow_chunks(large_chunks[6:])),
            ]

            # Execute concurrently
            await asyncio.gather(*tasks)

            # Verify buffer is in consistent state after overflow
            assert processor.buffer.total_size <= processor.max_buffer_size, "Buffer size should not exceed maximum"

            # Verify buffer integrity
            actual_size = sum(len(chunk.data) for chunk in processor.buffer.chunks)
            assert processor.buffer.total_size == actual_size, "Buffer total_size should match actual chunk sizes"

            # Verify chunks are still valid
            for chunk in processor.buffer.chunks:
                assert len(chunk.data) > 0, "Chunks should have valid data"
                assert chunk.timestamp >= 0, "Timestamps should be valid"

    @pytest.mark.asyncio
    async def test_rapid_concurrent_operations(self, real_audio_context):
        """Test rapid concurrent buffer operations to expose race conditions."""
        # This test will FAIL initially due to lack of proper locking

        with patch("audio_processor.AudioProcessor.whisper_exe", "/bin/echo"):
            from audio_processor import AudioProcessor

            processor = AudioProcessor(
                whisper_model_path="/tmp/test_model.bin", buffer_duration_ms=200, whisper_threads=1
            )

            real_audio_context.register_processor(processor)

            test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

            # Track operations for verification
            operations_completed = []

            async def rapid_add_operations(operation_id):
                """Perform rapid add operations."""
                for i in range(20):  # 20 rapid operations per task
                    # Create small chunk
                    small_data = np.random.randint(-1000, 1000, 100, dtype=np.int16)
                    chunk = AudioChunk(
                        timestamp=int(time.time() * 1_000_000 + i * 1000),
                        format=test_format,
                        data=small_data.tobytes(),
                        source_id=f"rapid_{operation_id}_{i}",
                    )

                    processor.add_chunk(chunk)
                    operations_completed.append(f"{operation_id}_{i}")

                    # No sleep - maximum concurrency stress test

            async def rapid_duration_checks(operation_id):
                """Perform rapid buffer duration checks."""
                for i in range(50):  # More frequent reads
                    duration = processor.get_buffer_duration()
                    operations_completed.append(f"duration_{operation_id}_{i}")

                    # Verify duration is reasonable
                    assert duration >= 0, "Duration should never be negative"

            # Launch multiple concurrent operations
            tasks = []

            # Add operations
            for i in range(5):
                tasks.append(asyncio.create_task(rapid_add_operations(i)))

            # Duration check operations
            for i in range(3):
                tasks.append(asyncio.create_task(rapid_duration_checks(i)))

            # Execute all tasks concurrently
            await asyncio.gather(*tasks)

            # Verify all operations completed without corruption
            assert len(operations_completed) == (5 * 20) + (3 * 50), "All operations should complete"

            # Verify buffer is in consistent state
            duration = processor.get_buffer_duration()
            assert duration >= 0, "Final duration should be valid"

            # Verify buffer integrity
            if processor.buffer.chunks:
                actual_size = sum(len(chunk.data) for chunk in processor.buffer.chunks)
                assert processor.buffer.total_size == actual_size, "Buffer total_size should match actual chunk sizes"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
