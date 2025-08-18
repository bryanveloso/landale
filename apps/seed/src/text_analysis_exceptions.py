"""Custom exceptions for text analysis pipeline.

This module defines specific exception types for better error handling
and debugging in the text analysis components of the Seed service.
"""


class TextAnalysisError(Exception):
    """Base exception for text analysis pipeline errors."""

    def __init__(self, message: str, context: dict[str, any] | None = None):
        super().__init__(message)
        self.context = context or {}


class ValidationError(TextAnalysisError):
    """Raised when input validation fails in text analysis schema."""

    pass


class ProcessingError(TextAnalysisError):
    """Raised when text processing operations fail."""

    pass


class SerializationError(TextAnalysisError):
    """Raised when serialization/deserialization operations fail."""

    pass


class CommunityAPIError(TextAnalysisError):
    """Raised when community API operations fail."""

    pass


class QuotesAPIError(TextAnalysisError):
    """Raised when quotes API operations fail."""

    pass


class VocabularyExtractionError(TextAnalysisError):
    """Raised when vocabulary extraction operations fail."""

    pass


class PreprocessingError(TextAnalysisError):
    """Raised when text preprocessing operations fail."""

    pass
