"""Test configuration and shared fixtures for Phononmaser TDD tests.

This module provides real audio test data and dependency infrastructure
for testing without mocking.
"""

import asyncio
import builtins
import contextlib
import shutil
import tempfile
from pathlib import Path

import pytest

from tests.fixtures.generate_test_audio import AudioTestDataGenerator


@pytest.fixture(scope="session")
def real_audio_generator():
    """Provide audio test data generator for the session."""
    return AudioTestDataGenerator()


@pytest.fixture(scope="session")
def test_audio_files(real_audio_generator):
    """Generate real audio test files for the session."""
    files = real_audio_generator.create_test_audio_files()
    yield files

    # Cleanup after session
    for filepath in files.values():
        if filepath.exists():
            filepath.unlink()


@pytest.fixture
def temp_audio_dir():
    """Provide temporary directory for audio processing tests."""
    temp_dir = Path(tempfile.mkdtemp())
    yield temp_dir

    # Cleanup
    shutil.rmtree(temp_dir, ignore_errors=True)


@pytest.fixture
def whisper_test_config():
    """Provide Whisper configuration for testing."""
    # Use a lightweight test model path or mock path for CI
    return {
        "model_path": "/tmp/test_whisper_model.bin",  # Test model
        "threads": 2,  # Reduced for testing
        "language": "en",
        "vad_model_path": "/tmp/test_vad_model.bin",  # Test VAD model
    }


@pytest.fixture
def real_audio_chunks(real_audio_generator):
    """Provide real audio chunks for streaming tests."""
    return real_audio_generator.create_streaming_audio_chunks(2.0, chunk_size=0.25)


@pytest.fixture
def overlapping_audio_chunks(real_audio_generator, test_audio_files):
    """Provide overlapping audio chunks for sliding window tests."""
    # Load the continuous speech file
    import wave

    import numpy as np

    with wave.open(str(test_audio_files["continuous_speech"]), "rb") as wav:
        frames = wav.readframes(wav.getnframes())
        audio_data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0

    return real_audio_generator.create_overlapping_chunks(audio_data, 1.5, 0.25)


@pytest.fixture
def asyncio_event_loop():
    """Provide event loop for async tests."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def mock_whisper_executable(temp_audio_dir, monkeypatch):
    """Create a mock whisper executable that returns predictable output."""
    mock_whisper = temp_audio_dir / "mock_whisper"

    # Create mock script that mimics whisper output
    mock_script = """#!/bin/bash
echo "[00:00:00.000 --> 00:00:01.500] This is test transcription."
"""

    mock_whisper.write_text(mock_script)
    mock_whisper.chmod(0o755)

    # Patch the whisper executable path
    monkeypatch.setattr("src.audio_processor.AudioProcessor.whisper_exe", str(mock_whisper))

    return mock_whisper


@pytest.fixture
def real_dependency_test_env(temp_audio_dir, whisper_test_config):
    """Set up real dependency testing environment without mocking."""
    test_env = {
        "temp_dir": temp_audio_dir,
        "whisper_config": whisper_test_config,
        "sample_rate": 16000,
        "channels": 1,
        "bit_depth": 16,
    }

    # Create test model files if they don't exist
    for model_path in [whisper_test_config["model_path"], whisper_test_config["vad_model_path"]]:
        Path(model_path).parent.mkdir(parents=True, exist_ok=True)
        if not Path(model_path).exists():
            # Create dummy model file for testing
            Path(model_path).write_bytes(b"dummy_model_data")

    return test_env


class RealAudioContext:
    """Context manager for real audio processing tests."""

    def __init__(self, audio_files: dict[str, Path], temp_dir: Path):
        self.audio_files = audio_files
        self.temp_dir = temp_dir
        self.active_processors = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        # Cleanup any active processors
        for processor in self.active_processors:
            if hasattr(processor, "stop"):
                with contextlib.suppress(builtins.BaseException):
                    asyncio.run(processor.stop())

    def register_processor(self, processor):
        """Register a processor for cleanup."""
        self.active_processors.append(processor)


@pytest.fixture
def real_audio_context(test_audio_files, temp_audio_dir):
    """Provide context manager for real audio processing tests."""
    return RealAudioContext(test_audio_files, temp_audio_dir)
