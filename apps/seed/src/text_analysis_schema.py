"""Standardized input schema for text analysis pipeline.

This module defines the unified data format that accepts text from multiple sources
(quotes, chat, voice transcription) while preserving source-specific metadata
for generalized processing in the Seed service.
"""

import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum

from .text_analysis_exceptions import ValidationError


class TextSource(Enum):
    """Source of the text input."""

    CHAT = "chat"
    QUOTES = "quotes"
    TRANSCRIPTION = "transcription"
    VOICE = "voice"  # Real-time voice input
    UNKNOWN = "unknown"


class TextCategory(Enum):
    """Category for text classification."""

    MESSAGE = "message"  # Regular conversation
    COMMAND = "command"  # Bot commands, actions
    QUOTE = "quote"  # Historical quotes
    TRANSCRIPTION = "transcription"  # Voice-to-text
    SYSTEM = "system"  # System-generated text


@dataclass
class UserInfo:
    """User information associated with text."""

    id: str | None = None
    username: str | None = None
    display_name: str | None = None
    preferred_name: str | None = None  # From community members
    platform: str | None = None  # twitch, discord, etc.


@dataclass
class SourceMetadata:
    """Source-specific metadata for text input."""

    # Chat-specific
    channel_id: str | None = None
    message_id: str | None = None
    emotes: list[str] = field(default_factory=list)
    badges: list[dict] = field(default_factory=list)

    # Quote-specific
    quote_id: str | None = None
    original_date: datetime | None = None
    context: str | None = None

    # Transcription-specific
    confidence: float | None = None
    audio_duration: float | None = None
    speaker_id: str | None = None

    # General
    session_id: str | None = None
    correlation_id: str | None = None
    raw_data: dict | None = None


@dataclass
class ProcessingHints:
    """Hints for text processing pipeline."""

    language: str | None = "en"
    priority: int = 0  # Higher = more important
    skip_vocabulary: bool = False
    skip_context_analysis: bool = False
    extract_entities: bool = True
    detect_sentiment: bool = False

    # Community-specific
    check_pronunciation: bool = True
    track_usage: bool = True


@dataclass
class TextAnalysisInput:
    """Standardized input for text analysis pipeline."""

    # Core fields (required)
    text: str
    source: TextSource
    category: TextCategory
    timestamp: datetime

    # Optional metadata
    user: UserInfo | None = None
    source_metadata: SourceMetadata | None = None
    processing_hints: ProcessingHints | None = None

    # Generated fields
    input_id: str | None = None  # Unique ID for this input
    parent_id: str | None = None  # For threaded/reply content

    def __post_init__(self):
        """Generate input ID if not provided."""
        if self.input_id is None:
            self.input_id = str(uuid.uuid4())

    @classmethod
    def from_chat_message(
        cls, message: str, user_id: str, username: str, display_name: str = None, **kwargs
    ) -> "TextAnalysisInput":
        """Create input from chat message."""
        user = UserInfo(id=user_id, username=username, display_name=display_name or username, platform="twitch")

        source_meta = SourceMetadata(
            message_id=kwargs.get("message_id"),
            emotes=kwargs.get("emotes", []),
            badges=kwargs.get("badges", []),
            correlation_id=kwargs.get("correlation_id"),
        )

        return cls(
            text=message,
            source=TextSource.CHAT,
            category=TextCategory.MESSAGE,
            timestamp=kwargs.get("timestamp", datetime.utcnow()),
            user=user,
            source_metadata=source_meta,
        )

    @classmethod
    def from_quote(
        cls, text: str, username: str, quote_id: str, original_date: datetime = None, context: str = None
    ) -> "TextAnalysisInput":
        """Create input from quote."""
        user = UserInfo(username=username)

        source_meta = SourceMetadata(quote_id=quote_id, original_date=original_date, context=context)

        return cls(
            text=text,
            source=TextSource.QUOTES,
            category=TextCategory.QUOTE,
            timestamp=datetime.utcnow(),
            user=user,
            source_metadata=source_meta,
        )

    @classmethod
    def from_transcription(
        cls, text: str, confidence: float, duration: float = None, speaker_id: str = None, **kwargs
    ) -> "TextAnalysisInput":
        """Create input from voice transcription."""
        source_meta = SourceMetadata(
            confidence=confidence,
            audio_duration=duration,
            speaker_id=speaker_id,
            session_id=kwargs.get("session_id"),
            correlation_id=kwargs.get("correlation_id"),
        )

        # Lower priority for low-confidence transcriptions
        hints = ProcessingHints(
            priority=-1 if confidence < 0.7 else 0,
            detect_sentiment=True,  # Useful for voice analysis
        )

        return cls(
            text=text,
            source=TextSource.TRANSCRIPTION,
            category=TextCategory.TRANSCRIPTION,
            timestamp=kwargs.get("timestamp", datetime.utcnow()),
            source_metadata=source_meta,
            processing_hints=hints,
        )

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        result = {
            "text": self.text,
            "source": self.source.value,
            "category": self.category.value,
            "timestamp": self.timestamp.isoformat(),
            "input_id": self.input_id,
            "parent_id": self.parent_id,
        }

        if self.user:
            result["user"] = {
                "id": self.user.id,
                "username": self.user.username,
                "display_name": self.user.display_name,
                "preferred_name": self.user.preferred_name,
                "platform": self.user.platform,
            }

        if self.source_metadata:
            result["source_metadata"] = {k: v for k, v in self.source_metadata.__dict__.items() if v is not None}
            # Convert datetime to ISO string
            if self.source_metadata.original_date:
                result["source_metadata"]["original_date"] = self.source_metadata.original_date.isoformat()

        if self.processing_hints:
            result["processing_hints"] = dict(self.processing_hints.__dict__.items())

        return result

    @classmethod
    def from_dict(cls, data: dict) -> "TextAnalysisInput":
        """Create from dictionary (JSON deserialization)."""
        # Parse timestamp with error handling
        try:
            timestamp = datetime.fromisoformat(data["timestamp"])
        except (ValueError, KeyError) as e:
            raise ValidationError(f"Invalid timestamp format: {data.get('timestamp', 'missing')}") from e

        # Parse user if present
        user = None
        if "user" in data:
            user_data = data["user"]
            user = UserInfo(
                id=user_data.get("id"),
                username=user_data.get("username"),
                display_name=user_data.get("display_name"),
                preferred_name=user_data.get("preferred_name"),
                platform=user_data.get("platform"),
            )

        # Parse source metadata if present
        source_metadata = None
        if "source_metadata" in data:
            meta_data = data["source_metadata"]
            # Convert original_date back to datetime if present
            if "original_date" in meta_data:
                try:
                    meta_data["original_date"] = datetime.fromisoformat(meta_data["original_date"])
                except (ValueError, TypeError) as e:
                    raise ValidationError(f"Invalid original_date format: {meta_data['original_date']}") from e
            source_metadata = SourceMetadata(**meta_data)

        # Parse processing hints if present
        processing_hints = None
        if "processing_hints" in data:
            processing_hints = ProcessingHints(**data["processing_hints"])

        return cls(
            text=data["text"],
            source=TextSource(data["source"]),
            category=TextCategory(data["category"]),
            timestamp=timestamp,
            user=user,
            source_metadata=source_metadata,
            processing_hints=processing_hints,
            input_id=data.get("input_id"),
            parent_id=data.get("parent_id"),
        )


@dataclass
class TextAnalysisOutput:
    """Output from text analysis pipeline."""

    # Reference to input
    input_id: str
    processed_at: datetime

    # Analysis results
    vocabulary_matches: list[str] = field(default_factory=list)
    potential_vocabulary: list[str] = field(default_factory=list)
    entities: list[dict] = field(default_factory=list)

    # Community analysis
    community_score: float = 0.0
    username_mentions: list[str] = field(default_factory=list)
    pronunciation_needed: list[str] = field(default_factory=list)
    community_context: dict | None = field(default_factory=dict)

    # Processing metadata
    processing_time_ms: int | None = None
    model_version: str | None = None
    error: str | None = None


# Convenience functions for common use cases


def create_chat_input(message: str, user_id: str, username: str, **kwargs) -> TextAnalysisInput:
    """Convenience function for creating chat inputs."""
    return TextAnalysisInput.from_chat_message(message, user_id, username, **kwargs)


def create_quote_input(text: str, username: str, quote_id: str, **kwargs) -> TextAnalysisInput:
    """Convenience function for creating quote inputs."""
    return TextAnalysisInput.from_quote(text, username, quote_id, **kwargs)


def create_transcription_input(text: str, confidence: float, **kwargs) -> TextAnalysisInput:
    """Convenience function for creating transcription inputs."""
    return TextAnalysisInput.from_transcription(text, confidence, **kwargs)


# Type aliases for common patterns
TextInputBatch = list[TextAnalysisInput]
TextOutputBatch = list[TextAnalysisOutput]
