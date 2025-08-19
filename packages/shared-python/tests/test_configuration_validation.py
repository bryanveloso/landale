"""Tests for configuration validation methods."""

import pytest

from shared.config.settings import PhononmaserConfig, SeedConfig, get_config


class TestPhononmaserConfigValidation:
    """Test PhononmaserConfig.validate() method with comprehensive error checking."""

    def test_valid_configuration_passes_validation(self):
        """Test that a valid configuration returns no errors."""
        config = PhononmaserConfig()

        # Set valid values
        config.port = 8889
        config.health_port = 8890
        config.sample_rate = 16000
        config.channels = 1
        config.buffer_size_mb = 100

        errors = config.validate()
        assert errors == []

    def test_default_configuration_is_valid(self):
        """Test that default PhononmaserConfig values are valid."""
        config = PhononmaserConfig()
        errors = config.validate()
        assert errors == []

    @pytest.mark.parametrize(
        "port,should_be_valid",
        [
            (1023, False),  # Below minimum
            (1024, True),  # At minimum
            (8889, True),  # Default value
            (65535, True),  # At maximum
            (65536, False),  # Above maximum
            (0, False),  # Zero
            (-1, False),  # Negative
        ],
    )
    def test_port_validation(self, port, should_be_valid):
        """Test port validation with boundary conditions."""
        config = PhononmaserConfig()
        config.port = port

        errors = config.validate()

        if should_be_valid:
            # Should not have port-related errors
            port_errors = [e for e in errors if "port" in e.lower() and "phononmaser port" in e]
            assert len(port_errors) == 0
        else:
            # Should have port validation error
            port_errors = [e for e in errors if "phononmaser port" in e and "out of valid range" in e]
            assert len(port_errors) == 1

    @pytest.mark.parametrize(
        "health_port,should_be_valid",
        [
            (1023, False),  # Below minimum
            (1024, True),  # At minimum
            (8890, True),  # Default value
            (65535, True),  # At maximum
            (65536, False),  # Above maximum
            (0, False),  # Zero
            (-1, False),  # Negative
        ],
    )
    def test_health_port_validation(self, health_port, should_be_valid):
        """Test health port validation with boundary conditions."""
        config = PhononmaserConfig()
        config.health_port = health_port

        errors = config.validate()

        if should_be_valid:
            # Should not have health port-related errors
            health_port_errors = [e for e in errors if "health check port" in e.lower() and "out of valid range" in e]
            assert len(health_port_errors) == 0
        else:
            # Should have health port validation error
            health_port_errors = [e for e in errors if "health check port" in e and "out of valid range" in e]
            assert len(health_port_errors) == 1

    def test_port_conflict_detection(self):
        """Test that same port for service and health check is detected."""
        config = PhononmaserConfig()
        config.port = 8889
        config.health_port = 8889  # Same as main port

        errors = config.validate()

        conflict_errors = [e for e in errors if "cannot be the same" in e]
        assert len(conflict_errors) == 1
        assert "8889" in conflict_errors[0]

    @pytest.mark.parametrize(
        "sample_rate,should_warn",
        [
            (8000, False),  # Standard rate
            (16000, False),  # Standard rate (default)
            (22050, False),  # Standard rate
            (44100, False),  # Standard rate
            (48000, False),  # Standard rate
            (11025, True),  # Non-standard rate
            (32000, True),  # Non-standard rate
            (96000, True),  # Non-standard rate
        ],
    )
    def test_sample_rate_validation(self, sample_rate, should_warn, caplog):
        """Test sample rate validation and warning for non-standard rates."""
        config = PhononmaserConfig()
        config.sample_rate = sample_rate

        errors = config.validate()

        # Sample rate warnings don't generate errors, just warnings
        assert len(errors) == 0

        if should_warn:
            assert f"Non-standard sample rate: {sample_rate}Hz" in caplog.text
        else:
            assert "Non-standard sample rate" not in caplog.text

    @pytest.mark.parametrize(
        "channels,should_be_valid",
        [
            (1, True),  # Mono (default)
            (2, True),  # Stereo
            (0, False),  # Invalid
            (3, False),  # Invalid
            (4, False),  # Invalid
            (-1, False),  # Invalid
        ],
    )
    def test_channels_validation(self, channels, should_be_valid):
        """Test audio channels validation."""
        config = PhononmaserConfig()
        config.channels = channels

        errors = config.validate()

        if should_be_valid:
            channel_errors = [e for e in errors if "channel count" in e.lower()]
            assert len(channel_errors) == 0
        else:
            channel_errors = [e for e in errors if "invalid channel count" in e.lower()]
            assert len(channel_errors) == 1

    @pytest.mark.parametrize(
        "buffer_size_mb,should_be_valid",
        [
            (0, False),  # Below minimum
            (1, True),  # At minimum
            (100, True),  # Default value
            (1000, True),  # At maximum
            (1001, False),  # Above maximum
            (-1, False),  # Negative
        ],
    )
    def test_buffer_size_validation(self, buffer_size_mb, should_be_valid):
        """Test buffer size validation."""
        config = PhononmaserConfig()
        config.buffer_size_mb = buffer_size_mb

        errors = config.validate()

        if should_be_valid:
            buffer_errors = [e for e in errors if "buffer size" in e.lower()]
            assert len(buffer_errors) == 0
        else:
            buffer_errors = [e for e in errors if "buffer size" in e.lower() and "out of reasonable range" in e]
            assert len(buffer_errors) == 1

    def test_multiple_validation_errors(self):
        """Test that multiple validation errors are all reported."""
        config = PhononmaserConfig()

        # Set multiple invalid values
        config.port = 500  # Invalid port
        config.health_port = 70000  # Invalid health port
        config.channels = 5  # Invalid channels
        config.buffer_size_mb = 2000  # Invalid buffer size

        errors = config.validate()

        # Should have all 4 validation errors
        assert len(errors) == 4

        # Check specific errors are present
        error_text = " ".join(errors)
        assert "phononmaser port 500" in error_text
        assert "health check port 70000" in error_text
        assert "invalid channel count: 5" in error_text.lower()
        assert "buffer size 2000mb" in error_text.lower()

    def test_edge_case_boundary_values(self):
        """Test edge cases at validation boundaries."""
        config = PhononmaserConfig()

        # Test exactly at boundaries (should be valid)
        config.port = 1024
        config.health_port = 65535
        config.buffer_size_mb = 1

        errors = config.validate()
        assert len(errors) == 0


class TestSeedConfigValidation:
    """Test SeedConfig.validate() method with comprehensive error checking."""

    def test_valid_configuration_passes_validation(self):
        """Test that a valid configuration returns no errors."""
        config = SeedConfig()

        # Set valid values
        config.port = 8891
        config.health_port = 8892
        config.lms_port = 1234
        config.lms_model = "meta/llama-3.3-70b"
        config.phononmaser_port = 8889

        errors = config.validate()
        assert errors == []

    def test_default_configuration_is_valid(self):
        """Test that default SeedConfig values are valid."""
        config = SeedConfig()
        errors = config.validate()
        assert errors == []

    @pytest.mark.parametrize(
        "port,should_be_valid",
        [
            (1023, False),  # Below minimum
            (1024, True),  # At minimum
            (8891, True),  # Default value
            (65535, True),  # At maximum
            (65536, False),  # Above maximum
            (0, False),  # Zero
            (-1, False),  # Negative
        ],
    )
    def test_port_validation(self, port, should_be_valid):
        """Test main port validation with boundary conditions."""
        config = SeedConfig()
        config.port = port

        errors = config.validate()

        if should_be_valid:
            # Should not have port-related errors
            port_errors = [e for e in errors if "seed port" in e.lower() and "out of valid range" in e]
            assert len(port_errors) == 0
        else:
            # Should have port validation error
            port_errors = [e for e in errors if "seed port" in e and "out of valid range" in e]
            assert len(port_errors) == 1

    @pytest.mark.parametrize(
        "health_port,should_be_valid",
        [
            (1023, False),  # Below minimum
            (1024, True),  # At minimum
            (8892, True),  # Default value
            (65535, True),  # At maximum
            (65536, False),  # Above maximum
            (0, False),  # Zero
            (-1, False),  # Negative
        ],
    )
    def test_health_port_validation(self, health_port, should_be_valid):
        """Test health port validation with boundary conditions."""
        config = SeedConfig()
        config.health_port = health_port

        errors = config.validate()

        if should_be_valid:
            # Should not have health port-related errors
            health_port_errors = [e for e in errors if "health check port" in e.lower() and "out of valid range" in e]
            assert len(health_port_errors) == 0
        else:
            # Should have health port validation error
            health_port_errors = [e for e in errors if "health check port" in e and "out of valid range" in e]
            assert len(health_port_errors) == 1

    def test_port_conflict_detection(self):
        """Test that same port for service and health check is detected."""
        config = SeedConfig()
        config.port = 8891
        config.health_port = 8891  # Same as main port

        errors = config.validate()

        conflict_errors = [e for e in errors if "cannot be the same" in e]
        assert len(conflict_errors) == 1
        assert "8891" in conflict_errors[0]

    @pytest.mark.parametrize(
        "lms_port,should_be_valid",
        [
            (0, False),  # Zero
            (1, True),  # At minimum
            (1234, True),  # Default value
            (65535, True),  # At maximum
            (65536, False),  # Above maximum
            (-1, False),  # Negative
        ],
    )
    def test_lms_port_validation(self, lms_port, should_be_valid):
        """Test LM Studio port validation."""
        config = SeedConfig()
        config.lms_port = lms_port

        errors = config.validate()

        if should_be_valid:
            lms_port_errors = [e for e in errors if "lm studio port" in e.lower() and "out of valid range" in e]
            assert len(lms_port_errors) == 0
        else:
            lms_port_errors = [e for e in errors if "lm studio port" in e.lower() and "out of valid range" in e]
            assert len(lms_port_errors) == 1

    @pytest.mark.parametrize(
        "lms_model,should_be_valid",
        [
            ("meta/llama-3.3-70b", True),  # Default valid model
            ("custom-model", True),  # Custom model name
            ("", False),  # Empty model name
            ("  ", False),  # Whitespace only
        ],
    )
    def test_lms_model_validation(self, lms_model, should_be_valid):
        """Test LM Studio model validation."""
        config = SeedConfig()
        config.lms_model = lms_model

        errors = config.validate()

        if should_be_valid:
            model_errors = [e for e in errors if "lms_model" in e.lower() and "cannot be empty" in e]
            assert len(model_errors) == 0
        else:
            model_errors = [e for e in errors if "lms_model" in e.lower() and "cannot be empty" in e]
            assert len(model_errors) == 1

    @pytest.mark.parametrize(
        "phononmaser_port,should_be_valid",
        [
            (1023, False),  # Below minimum
            (1024, True),  # At minimum
            (8889, True),  # Default value
            (65535, True),  # At maximum
            (65536, False),  # Above maximum
            (0, False),  # Zero
            (-1, False),  # Negative
        ],
    )
    def test_phononmaser_port_validation(self, phononmaser_port, should_be_valid):
        """Test Phononmaser connection port validation."""
        config = SeedConfig()
        config.phononmaser_port = phononmaser_port

        errors = config.validate()

        if should_be_valid:
            phono_port_errors = [e for e in errors if "phononmaser port" in e.lower() and "out of valid range" in e]
            assert len(phono_port_errors) == 0
        else:
            phono_port_errors = [e for e in errors if "phononmaser port" in e.lower() and "out of valid range" in e]
            assert len(phono_port_errors) == 1

    def test_multiple_validation_errors(self):
        """Test that multiple validation errors are all reported."""
        config = SeedConfig()

        # Set multiple invalid values
        config.port = 500  # Invalid port
        config.health_port = 70000  # Invalid health port
        config.lms_port = -1  # Invalid LMS port
        config.lms_model = ""  # Empty model
        config.phononmaser_port = 0  # Invalid Phononmaser port

        errors = config.validate()

        # Should have all 5 validation errors
        assert len(errors) == 5

        # Check specific errors are present
        error_text = " ".join(errors).lower()
        assert "seed port 500" in error_text
        assert "health check port 70000" in error_text
        assert "lm studio port -1" in error_text
        assert "lms_model" in error_text and "cannot be empty" in error_text
        assert "phononmaser port 0" in error_text

    def test_property_url_generation(self):
        """Test that URL properties are generated correctly."""
        config = SeedConfig()
        config.lms_host = "test-host"
        config.lms_port = 8080
        config.phononmaser_host = "phono-host"
        config.phononmaser_port = 9999

        assert config.lms_api_url == "http://test-host:8080/v1"
        assert config.phononmaser_url == "ws://phono-host:9999"

    def test_edge_case_boundary_values(self):
        """Test edge cases at validation boundaries."""
        config = SeedConfig()

        # Test exactly at boundaries (should be valid)
        config.port = 1024
        config.health_port = 65535
        config.lms_port = 1
        config.phononmaser_port = 1024

        errors = config.validate()
        assert len(errors) == 0


class TestConfigurationFactoryFunction:
    """Test the get_config factory function."""

    def test_get_phononmaser_config(self):
        """Test getting PhononmaserConfig via factory function."""
        config = get_config("phononmaser")
        assert isinstance(config, PhononmaserConfig)
        assert config.service_name == "phononmaser"

    def test_get_seed_config(self):
        """Test getting SeedConfig via factory function."""
        config = get_config("seed")
        assert isinstance(config, SeedConfig)
        assert config.service_name == "seed"

    def test_get_unknown_service_raises_error(self):
        """Test that unknown service name raises ValueError."""
        with pytest.raises(ValueError, match="Unknown service: unknown"):
            get_config("unknown")

    @pytest.mark.parametrize(
        "service_name",
        [
            "",  # Empty string
            "PHONONMASER",  # Wrong case
            "Seed",  # Wrong case
            "invalid",  # Invalid name
            "prometheus",  # Different service
        ],
    )
    def test_invalid_service_names(self, service_name):
        """Test various invalid service names."""
        with pytest.raises(ValueError):
            get_config(service_name)


class TestConfigurationIntegration:
    """Integration tests for configuration validation across services."""

    def test_both_services_have_different_default_ports(self):
        """Test that different services use different default ports."""
        phono_config = PhononmaserConfig()
        seed_config = SeedConfig()

        # Main service ports should be different
        assert phono_config.port != seed_config.port

        # Health check ports should be different
        assert phono_config.health_port != seed_config.health_port

        # No port conflicts between services
        all_ports = [
            phono_config.port,
            phono_config.health_port,
            seed_config.port,
            seed_config.health_port,
        ]
        assert len(set(all_ports)) == len(all_ports)  # All unique

    def test_service_can_connect_to_each_other(self):
        """Test that services can connect to each other with default config."""
        phono_config = PhononmaserConfig()
        seed_config = SeedConfig()

        # Seed should be able to connect to Phononmaser
        assert seed_config.phononmaser_port == phono_config.port

        # Both should use same server configuration
        assert phono_config.server_host == seed_config.server_host
        assert phono_config.server_ws_port == seed_config.server_ws_port

    def test_comprehensive_multi_service_validation(self):
        """Test validation when multiple services are configured."""
        phono_config = PhononmaserConfig()
        seed_config = SeedConfig()

        # Both configurations should be valid by default
        phono_errors = phono_config.validate()
        seed_errors = seed_config.validate()

        assert phono_errors == []
        assert seed_errors == []

    def test_configuration_error_message_quality(self):
        """Test that validation error messages are clear and actionable."""
        config = PhononmaserConfig()
        config.port = -1
        config.channels = 10

        errors = config.validate()

        # Error messages should be descriptive
        for error in errors:
            assert len(error) > 10  # Not just a code
            assert any(word in error.lower() for word in ["port", "channel", "range", "invalid"])

    def test_validation_performance_with_many_calls(self):
        """Test that validation doesn't have performance issues."""
        config = PhononmaserConfig()

        # Validation should be fast even with many calls
        for _ in range(1000):
            errors = config.validate()
            assert isinstance(errors, list)

    def test_configuration_immutability_during_validation(self):
        """Test that validation doesn't modify configuration values."""
        config = SeedConfig()

        # Capture original values
        original_port = config.port
        original_model = config.lms_model
        original_lms_port = config.lms_port

        # Run validation
        config.validate()

        # Values should be unchanged
        assert config.port == original_port
        assert config.lms_model == original_model
        assert config.lms_port == original_lms_port
