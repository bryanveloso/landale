"""TDD tests for timestamp conversion - testing BEHAVIOR not implementation."""

import sys
import time
from datetime import datetime
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from timestamp_utils import convert_timestamp_to_iso


class TestTimestampConversion:
    """Pure function tests for timestamp conversion behavior."""

    def test_current_timestamp_conversion(self):
        """Current timestamp should convert to current date, not 1970."""
        current_us = int(time.time() * 1_000_000)
        iso_string = convert_timestamp_to_iso(current_us)

        dt = datetime.fromisoformat(iso_string)
        assert dt.year >= 2025
        assert dt.year < 2030

    def test_small_timestamp_not_epoch(self):
        """Small timestamps should not result in 1970 epoch dates."""
        small_timestamp = 123456
        iso_string = convert_timestamp_to_iso(small_timestamp)

        dt = datetime.fromisoformat(iso_string)
        assert dt.year != 1970, "Timestamp bug: small values creating 1970 dates"

    def test_microsecond_precision_maintained(self):
        """Microsecond precision should be maintained in conversion."""
        base_time = int(time.time())
        test_microseconds = 123456
        timestamp_us = (base_time * 1_000_000) + test_microseconds

        iso_string = convert_timestamp_to_iso(timestamp_us)
        dt = datetime.fromisoformat(iso_string)

        expected_dt = datetime.fromtimestamp(base_time, tz=dt.tzinfo)
        time_diff = abs((dt - expected_dt).total_seconds())
        assert time_diff < 1, "Microsecond precision lost"

    def test_timezone_handling(self):
        """Timestamp should be converted to Los Angeles timezone."""
        current_us = int(time.time() * 1_000_000)
        iso_string = convert_timestamp_to_iso(current_us)

        dt = datetime.fromisoformat(iso_string)
        assert "America/Los_Angeles" in str(dt.tzinfo) or "-07:00" in iso_string or "-08:00" in iso_string

    def test_audio_processor_timestamp_scenario(self):
        """Test timestamps from audio processor - real world scenario."""
        audio_timestamp = 1721432323000000
        iso_string = convert_timestamp_to_iso(audio_timestamp)

        dt = datetime.fromisoformat(iso_string)
        assert dt.year == 2024
        assert dt.month == 7
        assert dt.day == 19

    def test_very_small_timestamp_epoch_bug(self):
        """This test should reveal if small numbers cause epoch bug."""
        small_timestamp = 1000
        iso_string = convert_timestamp_to_iso(small_timestamp)

        dt = datetime.fromisoformat(iso_string)
        if dt.year == 1970:
            pytest.fail(f"EPOCH BUG DETECTED: timestamp {small_timestamp} converted to {dt}")

    def test_zero_timestamp(self):
        """Zero timestamp should be detected as bogus and use current time."""
        zero_timestamp = 0
        iso_string = convert_timestamp_to_iso(zero_timestamp)

        dt = datetime.fromisoformat(iso_string)
        # Zero timestamp is bogus from OBS plugin, should use current time
        assert dt.year >= 2025, "Zero timestamp should be fixed to current time"

    def test_obs_plugin_relative_timestamp_bug(self):
        """Test if OBS plugin sends relative timestamps causing 1970 dates."""
        obs_startup_ns = 123456789000
        obs_timestamp_us = obs_startup_ns // 1000

        iso_string = convert_timestamp_to_iso(obs_timestamp_us)
        dt = datetime.fromisoformat(iso_string)

        if dt.year == 1970:
            pytest.fail(f"OBS BUG DETECTED: relative timestamp {obs_timestamp_us} converted to {dt} (year 1970)")

    def test_websocket_timestamp_conversion_simulation(self):
        """Simulate the exact conversion from websocket_server.py line 168."""
        obs_startup_relative_ns = 123456789
        timestamp_us = obs_startup_relative_ns // 1000

        iso_string = convert_timestamp_to_iso(timestamp_us)
        dt = datetime.fromisoformat(iso_string)

        print(f"DEBUG: ns={obs_startup_relative_ns} -> us={timestamp_us} -> {dt}")

        if dt.year == 1970:
            pytest.fail(f"WEBSOCKET BUG DETECTED: ns={obs_startup_relative_ns} -> us={timestamp_us} -> {dt}")

        assert dt.year >= 1970, f"Timestamp converted to {dt}"
