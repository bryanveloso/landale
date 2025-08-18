"""Text analysis pipeline integration module.

This module provides the main interface for text analysis using the standardized
input schema and vocabulary extraction algorithms.
"""

from datetime import datetime

from .community_api import contribute_analysis_to_community, enhance_analysis_with_community_context
from .logger import get_logger
from .text_analysis_exceptions import CommunityAPIError, ProcessingError
from .text_analysis_schema import (
    TextAnalysisInput,
    TextAnalysisOutput,
    create_chat_input,
    create_quote_input,
    create_transcription_input,
)
from .text_preprocessors import preprocess_text_batch, preprocess_text_input
from .vocabulary_extractor import VocabularyExtractor

logger = get_logger(__name__)


class TextAnalysisService:
    """Main service for processing text through the analysis pipeline."""

    def __init__(self, enable_community_integration: bool = True):
        self.vocabulary_extractor = VocabularyExtractor()
        self.enable_community_integration = enable_community_integration

    async def analyze_text(self, text_input: TextAnalysisInput) -> TextAnalysisOutput:
        """
        Analyze a text input through the full pipeline.

        Args:
            text_input: Standardized text input to analyze

        Returns:
            TextAnalysisOutput with analysis results
        """
        logger.debug(
            "Starting text analysis",
            input_id=text_input.input_id,
            source=text_input.source.value,
            category=text_input.category.value,
            text_length=len(text_input.text),
        )

        try:
            # Preprocess the text input
            preprocessed_input = preprocess_text_input(text_input)

            # Run vocabulary extraction on preprocessed text
            result = self.vocabulary_extractor.extract_vocabulary(preprocessed_input)

            # Enhance with community vocabulary context if enabled
            if self.enable_community_integration:
                try:
                    result = await enhance_analysis_with_community_context(result)

                    # Contribute discoveries back to community database
                    contributions = await contribute_analysis_to_community(result)

                    logger.debug("Community integration completed", input_id=text_input.input_id, **contributions)

                except CommunityAPIError as e:
                    logger.warning(
                        "Community integration failed, continuing without", input_id=text_input.input_id, error=str(e)
                    )
                except Exception as e:
                    # Log unexpected errors but continue processing
                    logger.warning(
                        "Unexpected error in community integration, continuing without",
                        input_id=text_input.input_id,
                        error=str(e),
                    )

            logger.info(
                "Text analysis completed",
                input_id=text_input.input_id,
                vocabulary_matches=len(result.vocabulary_matches),
                potential_vocabulary=len(result.potential_vocabulary),
                community_score=result.community_score,
                processing_time_ms=result.processing_time_ms,
            )

            return result

        except ProcessingError as e:
            logger.error("Text analysis processing failed", input_id=text_input.input_id, error=str(e))

            # Return error result
            return TextAnalysisOutput(input_id=text_input.input_id, processed_at=datetime.utcnow(), error=str(e))
        except Exception as e:
            logger.error("Unexpected error in text analysis", input_id=text_input.input_id, error=str(e))

            # Return error result
            return TextAnalysisOutput(
                input_id=text_input.input_id, processed_at=datetime.utcnow(), error=f"Unexpected error: {str(e)}"
            )

    async def analyze_chat_message(
        self, message: str, user_id: str, username: str, display_name: str = None, **kwargs
    ) -> TextAnalysisOutput:
        """
        Convenience method for analyzing chat messages.

        Args:
            message: Chat message text
            user_id: User ID
            username: Username
            display_name: Display name (optional)
            **kwargs: Additional metadata

        Returns:
            TextAnalysisOutput with analysis results
        """
        text_input = create_chat_input(message, user_id, username, display_name=display_name, **kwargs)
        return await self.analyze_text(text_input)

    async def analyze_quote(
        self, text: str, username: str, quote_id: str, original_date: datetime = None, context: str = None
    ) -> TextAnalysisOutput:
        """
        Convenience method for analyzing quotes.

        Args:
            text: Quote text
            username: Username who said it
            quote_id: Unique quote identifier
            original_date: When the quote was originally said
            context: Context information

        Returns:
            TextAnalysisOutput with analysis results
        """
        text_input = create_quote_input(text, username, quote_id, original_date=original_date, context=context)
        return await self.analyze_text(text_input)

    async def analyze_transcription(
        self, text: str, confidence: float, duration: float = None, speaker_id: str = None, **kwargs
    ) -> TextAnalysisOutput:
        """
        Convenience method for analyzing transcriptions.

        Args:
            text: Transcribed text
            confidence: Transcription confidence score
            duration: Audio duration in seconds
            speaker_id: Speaker identifier
            **kwargs: Additional metadata

        Returns:
            TextAnalysisOutput with analysis results
        """
        text_input = create_transcription_input(text, confidence, duration=duration, speaker_id=speaker_id, **kwargs)
        return await self.analyze_text(text_input)

    async def batch_analyze(self, text_inputs: list[TextAnalysisInput]) -> list[TextAnalysisOutput]:
        """
        Analyze multiple text inputs in batch.

        Args:
            text_inputs: List of text inputs to analyze

        Returns:
            List of analysis outputs
        """
        # Preprocess all inputs in batch for efficiency
        preprocessed_inputs = preprocess_text_batch(text_inputs)

        results = []

        for text_input in preprocessed_inputs:
            try:
                result = await self.analyze_text(text_input)
                results.append(result)
            except Exception as e:
                logger.error("Batch analysis item failed", input_id=text_input.input_id, error=str(e))

                # Add error result to maintain order
                error_result = TextAnalysisOutput(
                    input_id=text_input.input_id, processed_at=datetime.utcnow(), error=str(e)
                )
                results.append(error_result)

        logger.info(
            "Batch analysis completed",
            total_inputs=len(text_inputs),
            successful=len([r for r in results if not r.error]),
            failed=len([r for r in results if r.error]),
        )

        return results


# Global service instance for easy access
_text_analysis_service = None


def get_text_analysis_service() -> TextAnalysisService:
    """Get the global text analysis service instance."""
    global _text_analysis_service
    if _text_analysis_service is None:
        _text_analysis_service = TextAnalysisService(enable_community_integration=True)
    return _text_analysis_service


# Convenience functions for direct use
async def analyze_chat_message(message: str, user_id: str, username: str, **kwargs) -> dict:
    """
    Analyze a chat message and return results as dictionary.

    Args:
        message: Chat message text
        user_id: User ID
        username: Username
        **kwargs: Additional metadata

    Returns:
        Analysis results as dictionary
    """
    service = get_text_analysis_service()
    result = await service.analyze_chat_message(message, user_id, username, **kwargs)
    return result.to_dict() if hasattr(result, "to_dict") else result.__dict__


async def analyze_quote(text: str, username: str, quote_id: str, **kwargs) -> dict:
    """
    Analyze a quote and return results as dictionary.

    Args:
        text: Quote text
        username: Username who said it
        quote_id: Unique quote identifier
        **kwargs: Additional metadata

    Returns:
        Analysis results as dictionary
    """
    service = get_text_analysis_service()
    result = await service.analyze_quote(text, username, quote_id, **kwargs)
    return result.to_dict() if hasattr(result, "to_dict") else result.__dict__


async def analyze_transcription(text: str, confidence: float, **kwargs) -> dict:
    """
    Analyze transcription and return results as dictionary.

    Args:
        text: Transcribed text
        confidence: Transcription confidence score
        **kwargs: Additional metadata

    Returns:
        Analysis results as dictionary
    """
    service = get_text_analysis_service()
    result = await service.analyze_transcription(text, confidence, **kwargs)
    return result.to_dict() if hasattr(result, "to_dict") else result.__dict__
