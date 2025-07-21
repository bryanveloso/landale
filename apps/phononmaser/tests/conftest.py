"""Test configuration and shared fixtures for Phononmaser tests."""

import pytest

from tests.fixtures.generate_test_audio import AudioTestDataGenerator


@pytest.fixture(scope="session")
def real_audio_generator():
    """Provide audio test data generator for the session."""
    return AudioTestDataGenerator()
