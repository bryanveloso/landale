"""Pure timestamp conversion utilities."""

from datetime import datetime
from zoneinfo import ZoneInfo


def convert_timestamp_to_iso(timestamp_us: int, timezone_name: str = "America/Los_Angeles") -> str:
    """Convert microsecond timestamp to ISO 8601 string in specified timezone.

    Handles OBS plugin bug where it sends relative timestamps from startup
    instead of Unix epoch nanoseconds.

    Args:
        timestamp_us: Timestamp in microseconds since Unix epoch
        timezone_name: Target timezone name (default: America/Los_Angeles)

    Returns:
        ISO 8601 formatted timestamp string
    """
    # OBS plugin bug detection: if timestamp is too small, it's likely relative from startup
    # Unix epoch microseconds for 2024-01-01 is ~1,704,067,200,000,000
    # If timestamp is less than 1,000,000,000,000 (under ~2001), it's likely relative
    if timestamp_us < 1_000_000_000_000:
        # Use current time instead of bogus relative timestamp
        import time

        timestamp_seconds = time.time()
    else:
        timestamp_seconds = timestamp_us / 1_000_000

    tz = ZoneInfo(timezone_name)
    timestamp_dt = datetime.fromtimestamp(timestamp_seconds, tz=tz)
    return timestamp_dt.isoformat()
