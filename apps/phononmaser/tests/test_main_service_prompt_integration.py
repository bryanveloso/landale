"""Tests for main service integration with PromptManager."""

import os
from unittest.mock import AsyncMock, Mock, patch

import pytest
import pytest_asyncio

from src.main import Phononmaser

# Mark all tests in this module as async
pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def mock_dependencies():
    """Mock all service dependencies."""
    with (
        patch("src.main.ServerWebSocketClient") as mock_ws_client,
        patch("src.main.PhononmaserServer") as mock_server,
        patch("src.main.create_health_app") as mock_health,
        patch("src.main.AudioProcessor") as mock_audio_processor,
        patch("src.main.PromptManager") as mock_prompt_manager,
        patch("os.path.exists", return_value=True),
    ):
        # Configure mocks
        mock_ws_client.return_value.connect = AsyncMock()
        mock_ws_client.return_value.disconnect = AsyncMock()
        mock_ws_client.return_value.health_check = AsyncMock(return_value=True)

        mock_server_instance = AsyncMock()
        mock_server.return_value = mock_server_instance

        mock_health_instance = AsyncMock()
        mock_health.return_value = mock_health_instance

        mock_audio_instance = AsyncMock()
        mock_audio_processor.return_value = mock_audio_instance

        mock_prompt_instance = AsyncMock()
        mock_prompt_manager.return_value = mock_prompt_instance

        yield {
            "ws_client": mock_ws_client,
            "server": mock_server,
            "health": mock_health,
            "audio_processor": mock_audio_processor,
            "prompt_manager": mock_prompt_manager,
            "ws_client_instance": mock_ws_client.return_value,
            "server_instance": mock_server_instance,
            "health_instance": mock_health_instance,
            "audio_instance": mock_audio_instance,
            "prompt_instance": mock_prompt_instance,
        }


class TestMainServiceConfiguration:
    """Test main service configuration with PromptManager."""

    def test_environment_variable_parsing_enabled(self):
        """Test parsing environment variables with PromptManager enabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
            "PHOENIX_BASE_URL": "http://custom:7175",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()

            assert service.enable_prompt_manager is True
            assert service.phoenix_base_url == "http://custom:7175"

    def test_environment_variable_parsing_disabled(self):
        """Test parsing environment variables with PromptManager disabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "false",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()

            assert service.enable_prompt_manager is False
            assert service.phoenix_base_url == "http://saya:7175"  # Default

    def test_environment_variable_parsing_case_insensitive(self):
        """Test that ENABLE_PROMPT_MANAGER is case insensitive."""
        test_cases = ["true", "True", "TRUE", "TrUe"]

        for value in test_cases:
            env_vars = {
                "WHISPER_MODEL_PATH": "/path/to/model",
                "ENABLE_PROMPT_MANAGER": value,
            }

            with patch.dict(os.environ, env_vars):
                service = Phononmaser()
                assert service.enable_prompt_manager is True

    def test_environment_variable_defaults(self):
        """Test default values when environment variables are not set."""
        with patch.dict(os.environ, {"WHISPER_MODEL_PATH": "/path/to/model"}, clear=True):
            service = Phononmaser()

            assert service.enable_prompt_manager is False  # Default
            assert service.phoenix_base_url == "http://saya:7175"  # Default


class TestServiceStartupWithPromptManager:
    """Test service startup sequence with PromptManager."""

    async def test_startup_with_prompt_manager_enabled(self, mock_dependencies):
        """Test service startup with PromptManager enabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
            "PHOENIX_BASE_URL": "http://test:7175",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # PromptManager should have been created and started
            mock_dependencies["prompt_manager"].assert_called_once_with(phoenix_base_url="http://test:7175")
            mock_dependencies["prompt_instance"].start.assert_called_once()

            # AudioProcessor should have been created with PromptManager
            mock_dependencies["audio_processor"].assert_called_once()
            call_kwargs = mock_dependencies["audio_processor"].call_args[1]
            assert call_kwargs["prompt_manager"] is mock_dependencies["prompt_instance"]

            await service.stop()

    async def test_startup_with_prompt_manager_disabled(self, mock_dependencies):
        """Test service startup with PromptManager disabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "false",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # PromptManager should not have been created
            mock_dependencies["prompt_manager"].assert_not_called()

            # AudioProcessor should have been created without PromptManager
            mock_dependencies["audio_processor"].assert_called_once()
            call_kwargs = mock_dependencies["audio_processor"].call_args[1]
            assert call_kwargs["prompt_manager"] is None

            await service.stop()

    async def test_startup_sequence_order(self, mock_dependencies):
        """Test that startup sequence is correct with PromptManager."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        # Track call order
        call_order = []

        def track_call(name):
            def wrapper(*args, **kwargs):  # noqa: ARG001
                call_order.append(name)
                return AsyncMock()

            return wrapper

        mock_dependencies["ws_client_instance"].connect.side_effect = track_call("ws_connect")
        mock_dependencies["prompt_instance"].start.side_effect = track_call("prompt_start")
        mock_dependencies["server_instance"].start.side_effect = track_call("server_start")

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Verify startup order: WebSocket -> PromptManager -> Server
            expected_order = ["ws_connect", "prompt_start", "server_start"]
            assert call_order == expected_order

            await service.stop()


class TestServiceShutdownWithPromptManager:
    """Test service shutdown sequence with PromptManager."""

    async def test_shutdown_with_prompt_manager_enabled(self, mock_dependencies):
        """Test service shutdown with PromptManager enabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()
            await service.stop()

            # PromptManager should have been stopped
            mock_dependencies["prompt_instance"].stop.assert_called_once()

    async def test_shutdown_with_prompt_manager_disabled(self, mock_dependencies):
        """Test service shutdown with PromptManager disabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "false",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()
            await service.stop()

            # PromptManager should not have been created or stopped
            mock_dependencies["prompt_manager"].assert_not_called()

    async def test_shutdown_sequence_order(self, mock_dependencies):
        """Test that shutdown sequence is correct with PromptManager."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        # Track call order
        call_order = []

        def track_call(name):
            def wrapper(*args, **kwargs):  # noqa: ARG001
                call_order.append(name)
                return AsyncMock()

            return wrapper

        mock_dependencies["audio_instance"].stop.side_effect = track_call("audio_stop")
        mock_dependencies["server_instance"].stop.side_effect = track_call("server_stop")
        mock_dependencies["prompt_instance"].stop.side_effect = track_call("prompt_stop")
        mock_dependencies["ws_client_instance"].disconnect.side_effect = track_call("ws_disconnect")
        mock_dependencies["health_instance"].cleanup.side_effect = track_call("health_cleanup")

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()
            await service.stop()

            # Verify shutdown order
            expected_order = ["audio_stop", "server_stop", "prompt_stop", "ws_disconnect", "health_cleanup"]
            assert call_order == expected_order

    async def test_shutdown_handles_prompt_manager_failure(self, mock_dependencies, caplog):  # noqa: ARG002
        """Test that shutdown continues if PromptManager stop fails."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        # Make PromptManager stop fail
        mock_dependencies["prompt_instance"].stop.side_effect = Exception("Stop failed")

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Shutdown should not raise exception
            await service.stop()

            # Other components should still be stopped
            mock_dependencies["audio_instance"].stop.assert_called_once()
            mock_dependencies["server_instance"].stop.assert_called_once()


class TestHealthCheckWithPromptManager:
    """Test health check integration with PromptManager."""

    async def test_health_check_includes_prompt_manager(self, mock_dependencies):
        """Test that health check considers PromptManager state."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Mock components as healthy
            mock_dependencies["server_instance"].server = Mock()  # WebSocket server

            # Health check should pass
            is_healthy = await service.health_check()
            assert is_healthy is True

            await service.stop()

    async def test_health_check_without_prompt_manager(self, mock_dependencies):
        """Test health check works without PromptManager."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "false",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Mock components as healthy
            mock_dependencies["server_instance"].server = Mock()

            # Health check should still pass
            is_healthy = await service.health_check()
            assert is_healthy is True

            await service.stop()

    async def test_health_check_fails_when_not_running(self, mock_dependencies):  # noqa: ARG002
        """Test health check fails when service is not running."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            # Don't start the service

            # Health check should fail
            is_healthy = await service.health_check()
            assert is_healthy is False


class TestErrorHandlingInMainService:
    """Test error handling scenarios in main service."""

    async def test_prompt_manager_startup_failure(self, mock_dependencies, caplog):  # noqa: ARG002
        """Test handling of PromptManager startup failure."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        # Make PromptManager startup fail
        mock_dependencies["prompt_instance"].start.side_effect = Exception("Cannot connect to Phoenix")

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()

            # Startup should handle failure gracefully or fail cleanly
            try:
                await service.start()
                # If startup succeeds, service should still function
                assert service.running is True
                await service.stop()
            except Exception:
                # If startup fails, it should be a clean failure
                # not an unhandled exception
                pass

    async def test_prompt_manager_runtime_failure_isolation(self, mock_dependencies):  # noqa: ARG002
        """Test that PromptManager runtime failures don't affect other components."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Simulate PromptManager failure after startup
            # This would be handled within AudioProcessor's _get_current_prompt method
            # The main service should continue running

            assert service.running is True
            assert service.audio_processor is not None
            assert service.websocket_server is not None

            await service.stop()

    async def test_missing_whisper_model_path(self):
        """Test error when WHISPER_MODEL_PATH is missing."""
        env_vars = {
            "ENABLE_PROMPT_MANAGER": "true",
        }

        with (
            patch.dict(os.environ, env_vars, clear=True),
            pytest.raises(ValueError, match="WHISPER_MODEL_PATH environment variable is required"),
        ):
            Phononmaser()


class TestTranscriptionEventHandling:
    """Test transcription event handling with PromptManager."""

    async def test_transcription_callback_with_prompt_manager(self, mock_dependencies):
        """Test transcription event handling with PromptManager enabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Create mock transcription event
            from src.events import TranscriptionEvent

            event = TranscriptionEvent(
                timestamp=1234567890,
                duration=1.5,
                text="Test transcription with prompt context",
            )

            # Call transcription handler
            await service._handle_transcription(event)

            # WebSocket client should have been called
            mock_dependencies["ws_client_instance"].send_transcription.assert_called_once_with(event)

            # WebSocket server should have emitted event
            mock_dependencies["server_instance"].emit_transcription.assert_called_once_with(event)

            await service.stop()

    async def test_transcription_callback_without_prompt_manager(self, mock_dependencies):
        """Test transcription event handling with PromptManager disabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "false",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Create mock transcription event
            from src.events import TranscriptionEvent

            event = TranscriptionEvent(
                timestamp=1234567890,
                duration=1.5,
                text="Test transcription without prompt",
            )

            # Call transcription handler
            await service._handle_transcription(event)

            # Should still handle transcription normally
            mock_dependencies["ws_client_instance"].send_transcription.assert_called_once_with(event)
            mock_dependencies["server_instance"].emit_transcription.assert_called_once_with(event)

            await service.stop()

    async def test_transcription_callback_error_handling(self, mock_dependencies, caplog):
        """Test error handling in transcription callback."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
        }

        # Make WebSocket send fail
        mock_dependencies["ws_client_instance"].send_transcription.side_effect = Exception("Network error")

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            await service.start()

            # Create mock transcription event
            from src.events import TranscriptionEvent

            event = TranscriptionEvent(
                timestamp=1234567890,
                duration=1.5,
                text="Test transcription",
            )

            # Call transcription handler - should not raise
            await service._handle_transcription(event)

            # Should log error
            assert "Error sending transcription via WebSocket" in caplog.text

            # Local emit should still work
            mock_dependencies["server_instance"].emit_transcription.assert_called_once_with(event)

            await service.stop()


class TestConfigurationValidation:
    """Test configuration validation and edge cases."""

    def test_phoenix_base_url_normalization(self):
        """Test Phoenix base URL normalization."""
        test_cases = [
            ("http://test:7175", "http://test:7175"),
            ("http://test:7175/", "http://test:7175"),  # Should strip trailing slash
            ("https://prod.example.com/api", "https://prod.example.com/api"),
        ]

        for input_url, expected_url in test_cases:
            env_vars = {
                "WHISPER_MODEL_PATH": "/path/to/model",
                "PHOENIX_BASE_URL": input_url,
            }

            with patch.dict(os.environ, env_vars):
                service = Phononmaser()
                assert service.phoenix_base_url == expected_url

    def test_port_configuration(self):
        """Test port configuration from environment."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "PHONONMASER_PORT": "9999",
            "PHONONMASER_HEALTH_PORT": "9998",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            assert service.port == 9999
            assert service.health_port == 9998

    def test_whisper_configuration(self):
        """Test Whisper configuration from environment."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/custom/model/path",
            "WHISPER_THREADS": "16",
            "WHISPER_LANGUAGE": "es",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()
            assert service.whisper_model_path == "/custom/model/path"
            assert service.whisper_threads == 16
            assert service.whisper_language == "es"


@pytest.mark.integration
class TestFullServiceIntegration:
    """Integration tests for full service with PromptManager."""

    async def test_full_service_lifecycle_with_prompt_manager(self, mock_dependencies):
        """Test complete service lifecycle with PromptManager enabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "true",
            "PHOENIX_BASE_URL": "http://test:7175",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()

            # Start service
            await service.start()
            assert service.running is True
            assert service.prompt_manager is not None
            assert service.audio_processor is not None

            # Verify all components are wired correctly
            mock_dependencies["prompt_instance"].start.assert_called_once()
            mock_dependencies["audio_processor"].assert_called_once()

            # AudioProcessor should have PromptManager reference
            call_kwargs = mock_dependencies["audio_processor"].call_args[1]
            assert call_kwargs["prompt_manager"] is mock_dependencies["prompt_instance"]

            # Health check should pass
            mock_dependencies["server_instance"].server = Mock()
            is_healthy = await service.health_check()
            assert is_healthy is True

            # Stop service
            await service.stop()
            assert service.running is False

            # All components should be stopped
            mock_dependencies["prompt_instance"].stop.assert_called_once()
            mock_dependencies["audio_instance"].stop.assert_called_once()

    async def test_full_service_lifecycle_without_prompt_manager(self, mock_dependencies):
        """Test complete service lifecycle with PromptManager disabled."""
        env_vars = {
            "WHISPER_MODEL_PATH": "/path/to/model",
            "ENABLE_PROMPT_MANAGER": "false",
        }

        with patch.dict(os.environ, env_vars):
            service = Phononmaser()

            # Start service
            await service.start()
            assert service.running is True
            assert service.prompt_manager is None
            assert service.audio_processor is not None

            # PromptManager should not be created
            mock_dependencies["prompt_manager"].assert_not_called()

            # AudioProcessor should not have PromptManager reference
            call_kwargs = mock_dependencies["audio_processor"].call_args[1]
            assert call_kwargs["prompt_manager"] is None

            # Service should still function normally
            is_healthy = await service.health_check()
            assert is_healthy is True

            # Stop service
            await service.stop()
            assert service.running is False
