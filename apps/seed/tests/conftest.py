"""Test configuration and shared fixtures for Seed tests."""

import pytest
from unittest.mock import AsyncMock, MagicMock


@pytest.fixture
def mock_lms_client():
    """Mock LMS client for testing without API calls."""
    client = AsyncMock()
    client.analyze_with_fallback.return_value = MagicMock(
        sentiment="neutral", topics=["test"], patterns=None, chat_velocity=0.0
    )
    return client


@pytest.fixture
def mock_context_client():
    """Mock context client for testing without database."""
    client = AsyncMock()
    client.create_context.return_value = True
    return client


@pytest.fixture
def mock_logger():
    """Mock logger for testing."""
    logger = MagicMock()
    logger.info = MagicMock()
    logger.warning = MagicMock()
    logger.error = MagicMock()
    logger.debug = MagicMock()
    return logger
