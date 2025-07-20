"""TDD tests for overlap detection with real audio content.

Tests overlap detection using real transcription comparisons to identify
shared content between consecutive audio chunks.
"""

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from audio_processor import AudioChunk, AudioFormat


class TestOverlapDetection:
    """Test overlap detection with real audio content."""

    @pytest.mark.asyncio
    async def test_detect_overlap_in_consecutive_chunks(self, real_audio_context, overlapping_audio_chunks):
        """Test that overlap detection identifies shared content between consecutive chunks."""
        # This test will FAIL initially because OverlapDetector doesn't exist yet

        from overlap_detector import OverlapDetector

        detector = OverlapDetector(
            whisper_model_path="/tmp/test_model.bin",
            overlap_threshold_ms=200,  # 200ms minimum overlap
            similarity_threshold=0.8,  # 80% similarity required
        )

        real_audio_context.register_processor(detector)

        # Use real overlapping chunks from test data
        chunk1_audio, start1 = overlapping_audio_chunks[0]
        chunk2_audio, start2 = overlapping_audio_chunks[1]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        # Convert to audio chunks
        chunk1 = AudioChunk(
            timestamp=int(start1 * 1_000_000),  # Convert to microseconds
            format=test_format,
            data=(chunk1_audio * 32767).astype(np.int16).tobytes(),
            source_id="overlap_test_1",
        )

        chunk2 = AudioChunk(
            timestamp=int(start2 * 1_000_000),
            format=test_format,
            data=(chunk2_audio * 32767).astype(np.int16).tobytes(),
            source_id="overlap_test_2",
        )

        # Mock transcription results for overlap detection
        # These represent what Whisper would return for overlapping content
        transcription1 = "This is a test of the emergency broadcast system."
        transcription2 = "emergency broadcast system. This concludes our test."

        detector.mock_transcriptions = {
            chunk1.timestamp: transcription1,
            chunk2.timestamp: transcription2,
        }

        # Detect overlap between consecutive chunks
        overlap_result = await detector.detect_overlap(chunk1, chunk2)

        # Verify overlap detection results
        assert overlap_result is not None, "Should detect overlap in consecutive chunks"
        assert overlap_result.overlap_detected is True, "Should identify overlapping content"
        assert overlap_result.overlap_duration_ms >= 200, "Should meet minimum overlap threshold"
        assert overlap_result.similarity_score >= 0.7, "Should have reasonable similarity score"

        # Verify shared text identification
        expected_shared_text = "emergency broadcast system"
        assert expected_shared_text in overlap_result.shared_text, "Should identify shared transcription content"

        # Verify timing calculations
        assert overlap_result.chunk1_overlap_start >= 0, "Overlap start should be valid"
        assert overlap_result.chunk2_overlap_end >= 0, "Overlap end should be valid"

    @pytest.mark.asyncio
    async def test_no_overlap_in_distant_chunks(self, real_audio_context, test_audio_files):
        """Test that overlap detection correctly identifies no overlap in distant chunks."""

        from overlap_detector import OverlapDetector

        detector = OverlapDetector(
            whisper_model_path="/tmp/test_model.bin",
            overlap_threshold_ms=200,
            similarity_threshold=0.8,
        )

        # Create chunks from different parts of audio (no overlap)
        import wave

        with wave.open(str(test_audio_files["long_speech"]), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0

        # Extract non-overlapping segments
        chunk_samples = int(1.0 * 16000)  # 1 second chunks

        # First chunk from beginning
        chunk1_data = audio_data[:chunk_samples]
        # Second chunk from middle (no overlap)
        chunk2_data = audio_data[chunk_samples * 2 : chunk_samples * 3]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk1 = AudioChunk(
            timestamp=0,
            format=test_format,
            data=(chunk1_data * 32767).astype(np.int16).tobytes(),
            source_id="distant_test_1",
        )

        chunk2 = AudioChunk(
            timestamp=2_000_000,  # 2 seconds later
            format=test_format,
            data=(chunk2_data * 32767).astype(np.int16).tobytes(),
            source_id="distant_test_2",
        )

        # Mock completely different transcriptions
        detector.mock_transcriptions = {
            0: "The first part of the speech contains unique content.",
            2_000_000: "This is a completely different section with no shared words.",
        }

        # Detect overlap (should find none)
        overlap_result = await detector.detect_overlap(chunk1, chunk2)

        # Verify no overlap detected
        assert overlap_result is not None, "Should return result even with no overlap"
        assert overlap_result.overlap_detected is False, "Should not detect overlap in distant chunks"
        assert overlap_result.similarity_score < 0.8, "Similarity should be below threshold"
        assert overlap_result.shared_text == "", "Should have no shared text"

    @pytest.mark.asyncio
    async def test_partial_overlap_detection(self, real_audio_context, real_audio_generator):
        """Test detection of partial overlaps that meet minimum threshold."""

        from overlap_detector import OverlapDetector

        detector = OverlapDetector(
            whisper_model_path="/tmp/test_model.bin",
            overlap_threshold_ms=150,  # Lower threshold for partial overlaps
            similarity_threshold=0.6,  # Lower threshold for partial similarity
        )

        # Create test chunks with known partial overlap
        chunk_duration = 1.5  # 1.5 seconds
        overlap_duration = 0.3  # 300ms overlap

        base_audio = real_audio_generator.generate_speech_pattern(3.0)  # 3 seconds total

        # Create overlapping chunks
        chunk1_samples = int(chunk_duration * 16000)
        chunk2_start_samples = int((chunk_duration - overlap_duration) * 16000)
        chunk2_end_samples = chunk2_start_samples + chunk1_samples

        chunk1_data = base_audio[:chunk1_samples]
        chunk2_data = base_audio[chunk2_start_samples:chunk2_end_samples]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk1 = AudioChunk(
            timestamp=0,
            format=test_format,
            data=(chunk1_data * 32767).astype(np.int16).tobytes(),
            source_id="partial_test_1",
        )

        chunk2 = AudioChunk(
            timestamp=int((chunk_duration - overlap_duration) * 1_000_000),
            format=test_format,
            data=(chunk2_data * 32767).astype(np.int16).tobytes(),
            source_id="partial_test_2",
        )

        # Mock partial overlap transcriptions
        detector.mock_transcriptions = {
            0: "The weather is nice today and we should go outside.",
            int((chunk_duration - overlap_duration) * 1_000_000): "and we should go outside for a walk in the park.",
        }

        # Detect partial overlap
        overlap_result = await detector.detect_overlap(chunk1, chunk2)

        # Verify partial overlap detection
        assert overlap_result.overlap_detected is True, "Should detect partial overlap"
        assert 150 <= overlap_result.overlap_duration_ms <= 700, "Should detect reasonable overlap duration"
        assert overlap_result.similarity_score >= 0.6, "Should meet lowered similarity threshold"
        assert "and we should go outside" in overlap_result.shared_text, "Should identify shared phrase"

    @pytest.mark.asyncio
    async def test_overlap_detection_with_real_transcription_comparison(self, real_audio_context, test_audio_files):
        """Test overlap detection using actual transcription text comparison algorithms."""

        from overlap_detector import OverlapDetector

        detector = OverlapDetector(
            whisper_model_path="/tmp/test_model.bin",
            overlap_threshold_ms=100,
            similarity_threshold=0.7,
        )

        # Load real audio file and create overlapping chunks
        import wave

        with wave.open(str(test_audio_files["continuous_speech"]), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0

        # Create meaningful overlap scenario
        chunk_size = int(2.0 * 16000)  # 2 second chunks
        overlap_size = int(0.5 * 16000)  # 0.5 second overlap

        chunk1_data = audio_data[:chunk_size]
        chunk2_data = audio_data[chunk_size - overlap_size : chunk_size * 2 - overlap_size]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk1 = AudioChunk(
            timestamp=0,
            format=test_format,
            data=(chunk1_data * 32767).astype(np.int16).tobytes(),
            source_id="transcription_test_1",
        )

        chunk2 = AudioChunk(
            timestamp=1_500_000,  # 1.5 seconds
            format=test_format,
            data=(chunk2_data * 32767).astype(np.int16).tobytes(),
            source_id="transcription_test_2",
        )

        # Use realistic transcriptions that would have actual overlap
        detector.mock_transcriptions = {
            0: "In this comprehensive demonstration of our new audio processing system, we will showcase the advanced capabilities.",
            1_500_000: "audio processing system, we will showcase the advanced capabilities and real-time transcription accuracy.",
        }

        # Test real text comparison algorithms
        overlap_result = await detector.detect_overlap(chunk1, chunk2)

        # Verify sophisticated text comparison
        assert overlap_result.overlap_detected is True, "Should detect meaningful text overlap"

        # Verify the overlap detection used real text analysis
        expected_overlap = "audio processing system, we will showcase the advanced capabilities"
        similarity_words = set(expected_overlap.split()) & set(overlap_result.shared_text.split())
        assert len(similarity_words) >= 5, "Should identify multiple overlapping words"

        # Verify timing calculations are reasonable
        assert 400 <= overlap_result.overlap_duration_ms <= 600, "Should calculate ~500ms overlap duration"

    @pytest.mark.asyncio
    async def test_overlap_detector_handles_transcription_errors(self, real_audio_context, real_audio_chunks):
        """Test that overlap detector gracefully handles transcription failures."""

        from overlap_detector import OverlapDetector

        detector = OverlapDetector(
            whisper_model_path="/tmp/test_model.bin",
            overlap_threshold_ms=200,
            similarity_threshold=0.8,
        )

        chunk1_audio, start1 = real_audio_chunks[0]
        chunk2_audio, start2 = real_audio_chunks[1]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk1 = AudioChunk(
            timestamp=int(start1 * 1_000_000),
            format=test_format,
            data=(chunk1_audio * 32767).astype(np.int16).tobytes(),
            source_id="error_test_1",
        )

        chunk2 = AudioChunk(
            timestamp=int(start2 * 1_000_000),
            format=test_format,
            data=(chunk2_audio * 32767).astype(np.int16).tobytes(),
            source_id="error_test_2",
        )

        # Simulate transcription failure scenarios
        detector.mock_transcriptions = {
            chunk1.timestamp: None,  # Failed transcription
            chunk2.timestamp: "This is the second chunk transcription.",
        }

        # Should handle gracefully
        overlap_result = await detector.detect_overlap(chunk1, chunk2)

        assert overlap_result is not None, "Should return result even with transcription failure"
        assert overlap_result.overlap_detected is False, "Should not detect overlap with failed transcription"
        assert overlap_result.error_message is not None, "Should include error message"
        assert "transcription failed" in overlap_result.error_message.lower(), "Should explain transcription failure"

    @pytest.mark.asyncio
    async def test_overlap_detection_performance_with_large_chunks(self, real_audio_context, test_audio_files):
        """Test overlap detection performance with larger audio chunks."""

        import time

        from overlap_detector import OverlapDetector

        detector = OverlapDetector(
            whisper_model_path="/tmp/test_model.bin",
            overlap_threshold_ms=500,  # Larger overlap for large chunks
            similarity_threshold=0.75,
        )

        # Load continuous speech for large chunk testing
        import wave

        with wave.open(str(test_audio_files["continuous_speech"]), "rb") as wav:
            frames = wav.readframes(wav.getnframes())
            audio_data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0

        # Create large chunks (5 seconds each with 1 second overlap)
        large_chunk_size = int(5.0 * 16000)
        overlap_size = int(1.0 * 16000)

        chunk1_data = audio_data[:large_chunk_size]
        chunk2_data = audio_data[large_chunk_size - overlap_size : large_chunk_size * 2 - overlap_size]

        test_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)

        chunk1 = AudioChunk(
            timestamp=0,
            format=test_format,
            data=(chunk1_data * 32767).astype(np.int16).tobytes(),
            source_id="large_test_1",
        )

        chunk2 = AudioChunk(
            timestamp=4_000_000,  # 4 seconds (5 - 1 overlap)
            format=test_format,
            data=(chunk2_data * 32767).astype(np.int16).tobytes(),
            source_id="large_test_2",
        )

        # Mock large transcriptions
        detector.mock_transcriptions = {
            0: "This is a very long transcription that represents what we might get from a five second audio chunk with lots of detailed speech content that goes on and on with multiple sentences and complex ideas.",
            4_000_000: "detailed speech content that goes on and on with multiple sentences and complex ideas. Now we continue with the second part of this extended speech segment.",
        }

        # Measure performance
        start_time = time.time()
        overlap_result = await detector.detect_overlap(chunk1, chunk2)
        detection_time = time.time() - start_time

        # Verify performance and accuracy
        assert detection_time < 1.0, "Overlap detection should complete within 1 second"
        assert overlap_result.overlap_detected is True, "Should detect overlap in large chunks"
        assert overlap_result.overlap_duration_ms >= 500, "Should meet minimum overlap threshold for large chunks"


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
