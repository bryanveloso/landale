"""Generate real audio test data for TDD validation.

This module creates authentic audio files with known speech content to test
transcription optimization without mocking.
"""

import wave
from pathlib import Path

import numpy as np


class AudioTestDataGenerator:
    """Generates real audio test data for transcription testing."""

    def __init__(self, sample_rate: int = 16000):
        self.sample_rate = sample_rate
        self.fixtures_dir = Path(__file__).parent
        self.fixtures_dir.mkdir(exist_ok=True)

    def generate_silence(self, duration_seconds: float) -> np.ndarray:
        """Generate silent audio."""
        samples = int(duration_seconds * self.sample_rate)
        return np.zeros(samples, dtype=np.float32)

    def generate_tone(self, frequency: float, duration_seconds: float, amplitude: float = 0.3) -> np.ndarray:
        """Generate a simple sine wave tone."""
        samples = int(duration_seconds * self.sample_rate)
        t = np.linspace(0, duration_seconds, samples, False)
        return (amplitude * np.sin(2 * np.pi * frequency * t)).astype(np.float32)

    def generate_speech_pattern(self, duration_seconds: float) -> np.ndarray:
        """Generate audio that mimics speech patterns for VAD testing."""
        samples = int(duration_seconds * self.sample_rate)

        # Generate multiple frequency components to simulate speech formants
        t = np.linspace(0, duration_seconds, samples, False)

        # Fundamental frequency (similar to human speech)
        f0 = 150 + 50 * np.sin(2 * np.pi * 2 * t)  # Varying pitch

        # Formant frequencies
        f1 = 800 + 200 * np.sin(2 * np.pi * 3 * t)
        f2 = 1200 + 300 * np.sin(2 * np.pi * 1.5 * t)
        f3 = 2400 + 400 * np.sin(2 * np.pi * 0.8 * t)

        # Combine formants with decreasing amplitude
        signal = (
            0.5 * np.sin(2 * np.pi * f0 * t)
            + 0.3 * np.sin(2 * np.pi * f1 * t)
            + 0.2 * np.sin(2 * np.pi * f2 * t)
            + 0.1 * np.sin(2 * np.pi * f3 * t)
        )

        # Add envelope to simulate speech dynamics
        envelope = np.exp(-0.5 * ((t - duration_seconds / 2) / (duration_seconds / 4)) ** 2)
        signal *= envelope

        # Add some noise for realism
        noise = 0.02 * np.random.normal(0, 1, samples)
        signal += noise

        # Normalize
        signal = signal / np.max(np.abs(signal)) * 0.7

        return signal.astype(np.float32)

    def generate_noise_pattern(
        self, duration: float, noise_type: str = "gaming", noise_level: float = 0.1
    ) -> np.ndarray:
        """Generate background noise patterns for gaming/streaming scenarios."""
        samples = int(duration * self.sample_rate)
        t = np.linspace(0, duration, samples, False)

        if noise_type == "gaming":
            # Simulate gaming background noise: keyboard clicks, low-level game audio

            # Base white noise (general electronic noise)
            base_noise = noise_level * 0.3 * np.random.normal(0, 1, samples)

            # Keyboard click simulation (periodic sharp transients)
            click_frequency = 2.0  # ~2 clicks per second
            click_times = np.random.poisson(click_frequency, int(duration * click_frequency))
            keyboard_noise = np.zeros(samples)

            for i, click_count in enumerate(click_times):
                if i < duration:
                    click_start = int(i * self.sample_rate)
                    for _ in range(click_count):
                        if click_start < samples - 100:
                            # Sharp click transient
                            click_duration = 0.005  # 5ms click
                            click_samples = int(click_duration * self.sample_rate)
                            click_envelope = np.exp(-np.linspace(0, 10, click_samples))
                            click_signal = noise_level * 0.5 * click_envelope * np.random.normal(0, 1, click_samples)

                            end_idx = min(click_start + click_samples, samples)
                            keyboard_noise[click_start:end_idx] += click_signal[: end_idx - click_start]
                            click_start += int(0.1 * self.sample_rate)  # Space clicks apart

            # Low-frequency game audio simulation (distant game sounds)
            game_frequencies = [60, 120, 180, 240]  # Low frequency rumble
            game_audio = np.zeros(samples)
            for freq in game_frequencies:
                amplitude = noise_level * 0.2 * np.random.uniform(0.5, 1.0)
                phase = np.random.uniform(0, 2 * np.pi)
                game_audio += amplitude * np.sin(2 * np.pi * freq * t + phase)

            # Combine all noise components
            total_noise = base_noise + keyboard_noise + game_audio

        else:
            # Default: white noise
            total_noise = noise_level * np.random.normal(0, 1, samples)

        return total_noise.astype(np.float32)

    def create_wav_file(self, audio_data: np.ndarray, filename: str) -> Path:
        """Create a WAV file from audio data."""
        filepath = self.fixtures_dir / filename

        # Convert float32 to int16 for WAV
        audio_int16 = (audio_data * 32767).astype(np.int16)

        with wave.open(str(filepath), "wb") as wav_file:
            wav_file.setnchannels(1)  # Mono
            wav_file.setsampwidth(2)  # 16-bit
            wav_file.setframerate(self.sample_rate)
            wav_file.writeframes(audio_int16.tobytes())

        return filepath

    def create_streaming_audio_chunks(
        self, total_duration: float, chunk_size: float = 0.1
    ) -> list[tuple[np.ndarray, float]]:
        """Create overlapping audio chunks to simulate streaming."""
        chunks = []
        current_time = 0.0

        while current_time < total_duration:
            chunk_duration = min(chunk_size, total_duration - current_time)

            # Generate speech-like audio for this chunk
            chunk_audio = self.generate_speech_pattern(chunk_duration)

            chunks.append((chunk_audio, current_time))
            current_time += chunk_duration

        return chunks

    def create_overlapping_chunks(
        self, base_audio: np.ndarray, chunk_duration: float, overlap_duration: float
    ) -> list[tuple[np.ndarray, float]]:
        """Create overlapping chunks from base audio."""
        chunk_samples = int(chunk_duration * self.sample_rate)
        overlap_samples = int(overlap_duration * self.sample_rate)
        step_samples = chunk_samples - overlap_samples

        chunks = []
        start_sample = 0

        while start_sample + chunk_samples <= len(base_audio):
            end_sample = start_sample + chunk_samples
            chunk = base_audio[start_sample:end_sample]
            start_time = start_sample / self.sample_rate

            chunks.append((chunk, start_time))
            start_sample += step_samples

        # Handle final chunk if there's remaining audio
        if start_sample < len(base_audio):
            chunk = base_audio[start_sample:]
            # Pad with zeros if needed
            if len(chunk) < chunk_samples:
                padding = np.zeros(chunk_samples - len(chunk), dtype=np.float32)
                chunk = np.concatenate([chunk, padding])

            start_time = start_sample / self.sample_rate
            chunks.append((chunk, start_time))

        return chunks

    def create_test_audio_files(self) -> dict:
        """Create all necessary test audio files."""
        files = {}

        # Short speech-like audio for basic testing
        short_speech = self.generate_speech_pattern(2.0)
        files["short_speech"] = self.create_wav_file(short_speech, "short_speech.wav")

        # Longer audio for overlap testing
        long_speech = self.generate_speech_pattern(5.0)
        files["long_speech"] = self.create_wav_file(long_speech, "long_speech.wav")

        # Audio with silence gaps for VAD testing
        speech_with_gaps = np.concatenate(
            [
                self.generate_speech_pattern(1.0),
                self.generate_silence(0.5),
                self.generate_speech_pattern(1.5),
                self.generate_silence(0.3),
                self.generate_speech_pattern(0.8),
            ]
        )
        files["speech_with_gaps"] = self.create_wav_file(speech_with_gaps, "speech_with_gaps.wav")

        # Very short chunks for boundary testing
        very_short = self.generate_speech_pattern(0.1)
        files["very_short"] = self.create_wav_file(very_short, "very_short.wav")

        # Continuous speech for sliding window testing
        continuous_speech = self.generate_speech_pattern(10.0)
        files["continuous_speech"] = self.create_wav_file(continuous_speech, "continuous_speech.wav")

        return files


if __name__ == "__main__":
    generator = AudioTestDataGenerator()
    files = generator.create_test_audio_files()

    print("Generated test audio files:")
    for name, path in files.items():
        print(f"  {name}: {path}")
        print(f"    Size: {path.stat().st_size} bytes")
