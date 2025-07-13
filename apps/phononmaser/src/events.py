"""Event definitions for phononmaser."""

from dataclasses import dataclass


@dataclass
class TranscriptionEvent:
    """Audio transcription event."""

    timestamp: int  # microseconds
    duration: float  # seconds
    text: str
