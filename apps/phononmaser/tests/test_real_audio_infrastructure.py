"""Test real audio test data infrastructure.

Validates that our audio generation works correctly and produces usable test data.
"""

import wave

import numpy as np
import pytest
from fixtures.generate_test_audio import AudioTestDataGenerator


class TestAudioTestDataGenerator:
    """Test the audio test data generator produces valid audio."""

    def test_generator_initialization(self):
        """Test that generator initializes correctly."""
        generator = AudioTestDataGenerator()
        assert generator.sample_rate == 16000
        assert generator.fixtures_dir.exists()

    def test_silence_generation(self):
        """Test silence generation produces correct duration and values."""
        generator = AudioTestDataGenerator()
        silence = generator.generate_silence(1.0)

        # Check duration (1 second at 16kHz = 16000 samples)
        assert len(silence) == 16000

        # Check that it's actually silent
        assert np.all(silence == 0)
        assert silence.dtype == np.float32

    def test_tone_generation(self):
        """Test tone generation produces correct frequency and amplitude."""
        generator = AudioTestDataGenerator()
        tone = generator.generate_tone(440.0, 1.0, amplitude=0.5)

        # Check duration
        assert len(tone) == 16000
        assert tone.dtype == np.float32

        # Check amplitude is reasonable
        assert np.max(np.abs(tone)) <= 0.5
        assert np.max(np.abs(tone)) > 0.4  # Should be close to requested amplitude

    def test_speech_pattern_generation(self):
        """Test speech pattern generation produces realistic audio."""
        generator = AudioTestDataGenerator()
        speech = generator.generate_speech_pattern(2.0)

        # Check duration
        assert len(speech) == 32000  # 2 seconds at 16kHz
        assert speech.dtype == np.float32

        # Check amplitude is normalized
        assert np.max(np.abs(speech)) <= 1.0
        assert np.max(np.abs(speech)) > 0.1  # Should have reasonable amplitude

        # Check it's not just silence or a pure tone
        # Real speech should have varying amplitude
        rms_values = []
        chunk_size = 1600  # 0.1 second chunks
        for i in range(0, len(speech) - chunk_size, chunk_size):
            chunk = speech[i : i + chunk_size]
            rms = np.sqrt(np.mean(chunk**2))
            rms_values.append(rms)

        # RMS should vary (not constant like a pure tone)
        rms_std = np.std(rms_values)
        assert rms_std > 0.01  # Some variation in amplitude

    def test_wav_file_creation(self):
        """Test WAV file creation and format."""
        generator = AudioTestDataGenerator()
        test_audio = generator.generate_tone(440.0, 0.5)

        # Create temporary file
        filepath = generator.create_wav_file(test_audio, "test_tone.wav")

        try:
            # Verify file exists
            assert filepath.exists()

            # Verify WAV file properties
            with wave.open(str(filepath), "rb") as wav_file:
                assert wav_file.getnchannels() == 1  # Mono
                assert wav_file.getsampwidth() == 2  # 16-bit
                assert wav_file.getframerate() == 16000  # 16kHz
                assert wav_file.getnframes() == 8000  # 0.5 seconds
        finally:
            # Cleanup
            if filepath.exists():
                filepath.unlink()

    def test_streaming_chunks_creation(self):
        """Test streaming audio chunks generation."""
        generator = AudioTestDataGenerator()
        chunks = generator.create_streaming_audio_chunks(1.0, chunk_size=0.25)

        # Should have 4 chunks for 1 second with 0.25s chunks
        assert len(chunks) == 4

        # Each chunk should be correct duration
        for chunk_audio, _start_time in chunks:
            assert len(chunk_audio) == 4000  # 0.25s at 16kHz
            assert chunk_audio.dtype == np.float32

        # Start times should be sequential
        start_times = [start_time for _, start_time in chunks]
        expected_times = [0.0, 0.25, 0.5, 0.75]
        assert start_times == expected_times

    def test_overlapping_chunks_creation(self):
        """Test overlapping chunks from base audio."""
        generator = AudioTestDataGenerator()
        base_audio = generator.generate_speech_pattern(2.0)  # 2 seconds

        # Create overlapping chunks: 0.5s chunks with 0.1s overlap
        chunks = generator.create_overlapping_chunks(base_audio, 0.5, 0.1)

        # Should have multiple overlapping chunks
        assert len(chunks) >= 4  # At least 4 chunks for 2s audio with 0.4s step

        # Each chunk should be correct size
        for chunk_audio, _start_time in chunks:
            assert len(chunk_audio) == 8000  # 0.5s at 16kHz
            assert chunk_audio.dtype == np.float32

        # Verify overlap: consecutive chunks should share audio
        chunk1_audio, start1 = chunks[0]
        chunk2_audio, start2 = chunks[1]

        # Time difference should be chunk_duration - overlap_duration = 0.4s
        assert abs((start2 - start1) - 0.4) < 0.01

        # Extract overlapping region from original audio
        overlap_start_samples = int((start1 + 0.4) * 16000)  # Start of overlap in original
        overlap_end_samples = int((start1 + 0.5) * 16000)  # End of overlap in original

        overlap_from_original = base_audio[overlap_start_samples:overlap_end_samples]
        overlap_from_chunk1 = chunk1_audio[-1600:]  # Last 0.1s of chunk1
        overlap_from_chunk2 = chunk2_audio[:1600]  # First 0.1s of chunk2

        # Overlapping regions should match the original
        np.testing.assert_array_almost_equal(overlap_from_chunk1, overlap_from_original, decimal=5)
        np.testing.assert_array_almost_equal(overlap_from_chunk2, overlap_from_original, decimal=5)

    def test_create_test_audio_files(self):
        """Test creation of all test audio files."""
        generator = AudioTestDataGenerator()
        files = generator.create_test_audio_files()

        expected_files = ["short_speech", "long_speech", "speech_with_gaps", "very_short", "continuous_speech"]

        try:
            # Verify all expected files are created
            for name in expected_files:
                assert name in files
                assert files[name].exists()
                assert files[name].suffix == ".wav"

            # Verify file sizes are reasonable
            assert files["short_speech"].stat().st_size > 1000  # At least 1KB
            assert files["long_speech"].stat().st_size > files["short_speech"].stat().st_size
            assert files["continuous_speech"].stat().st_size > files["long_speech"].stat().st_size

        finally:
            # Cleanup test files
            for filepath in files.values():
                if filepath.exists():
                    filepath.unlink()

    def test_wav_file_format_compatibility(self):
        """Test that generated WAV files are compatible with standard tools."""
        generator = AudioTestDataGenerator()
        test_audio = generator.generate_speech_pattern(1.0)
        filepath = generator.create_wav_file(test_audio, "format_test.wav")

        try:
            # Read back the file and verify content
            with wave.open(str(filepath), "rb") as wav_file:
                frames = wav_file.readframes(wav_file.getnframes())

                # Convert back to numpy array
                audio_int16 = np.frombuffer(frames, dtype=np.int16)
                audio_float = audio_int16.astype(np.float32) / 32767.0

                # Should be similar to original (within quantization error)
                # Use correlation to check similarity since exact match is unlikely due to quantization
                correlation = np.corrcoef(test_audio, audio_float)[0, 1]
                assert correlation > 0.99  # Very high correlation

        finally:
            if filepath.exists():
                filepath.unlink()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
