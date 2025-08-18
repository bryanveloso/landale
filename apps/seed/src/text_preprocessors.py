"""Source-specific text preprocessors for the text analysis pipeline.

This module provides specialized preprocessing for different text sources (quotes, chat, voice)
to normalize and clean text before vocabulary extraction and analysis.
"""

import re
import unicodedata
from abc import ABC, abstractmethod

from .logger import get_logger
from .text_analysis_schema import TextAnalysisInput, TextSource

logger = get_logger(__name__)


class BaseTextPreprocessor(ABC):
    """Base class for text preprocessors."""

    def __init__(self):
        """Initialize the preprocessor."""
        self.processed_count = 0
        self.error_count = 0

    @abstractmethod
    def preprocess(self, text_input: TextAnalysisInput) -> TextAnalysisInput:
        """Preprocess a text input.

        Args:
            text_input: Input to preprocess

        Returns:
            Preprocessed text input
        """
        pass

    def _normalize_unicode(self, text: str) -> str:
        """Normalize unicode characters to consistent form."""
        # Normalize to NFC (canonical decomposition, then canonical composition)
        normalized = unicodedata.normalize("NFC", text)
        return normalized

    def _remove_excessive_whitespace(self, text: str) -> str:
        """Remove excessive whitespace while preserving intentional spacing."""
        # Replace multiple whitespace with single space
        text = re.sub(r"\s+", " ", text)
        # Remove leading/trailing whitespace
        text = text.strip()
        return text

    def _preserve_intentional_repetition(self, text: str) -> str:
        """Preserve intentional character repetition for emphasis."""
        # Don't modify text here - let vocabulary extractor detect patterns
        return text


class QuotesPreprocessor(BaseTextPreprocessor):
    """Preprocessor for historical quotes data."""

    def __init__(self):
        super().__init__()

        # Common quote formatting patterns to clean
        self.quote_markers = ['"', "'", '"', '"', """, """]
        self.attribution_patterns = [
            r"\s*-\s*\w+.*$",  # - username
            r"\s*~\s*\w+.*$",  # ~ username
            r"\s*\(\w+.*\)$",  # (username)
        ]

        # Game name patterns in context
        self.game_context_patterns = [
            r"(?:playing|in|during|from)\s+([A-Z][^,\n]*?)(?:\s*[,\n]|$)",
            r"Game:\s*([^,\n]+)",
            r"\[([^]]+)\]",  # [Game Name]
        ]

    def preprocess(self, text_input: TextAnalysisInput) -> TextAnalysisInput:
        """Preprocess quote text.

        Args:
            text_input: Quote input to preprocess

        Returns:
            Preprocessed quote input
        """
        try:
            if text_input.source != TextSource.QUOTES:
                logger.warning(
                    "QuotesPreprocessor received non-quote input",
                    source=text_input.source.value,
                    input_id=text_input.input_id,
                )
                return text_input

            original_text = text_input.text
            processed_text = original_text

            # Remove quote markers
            processed_text = self._remove_quote_markers(processed_text)

            # Remove attribution suffixes (- username, etc)
            processed_text = self._remove_attribution(processed_text)

            # Extract game context if available
            game_context = self._extract_game_context(original_text)

            # Unicode normalization
            processed_text = self._normalize_unicode(processed_text)

            # Clean excessive whitespace
            processed_text = self._remove_excessive_whitespace(processed_text)

            # Preserve intentional repetition
            processed_text = self._preserve_intentional_repetition(processed_text)

            # Update text input
            text_input.text = processed_text

            # Add extracted game context to metadata if found
            if game_context and text_input.source_metadata:
                if text_input.source_metadata.context:
                    text_input.source_metadata.context += f" | Game: {game_context}"
                else:
                    text_input.source_metadata.context = f"Game: {game_context}"

            self.processed_count += 1

            logger.debug(
                "Preprocessed quote",
                input_id=text_input.input_id,
                original_length=len(original_text),
                processed_length=len(processed_text),
                game_context=game_context,
            )

            return text_input

        except Exception as e:
            logger.error("Failed to preprocess quote", input_id=text_input.input_id, error=str(e))
            self.error_count += 1
            return text_input  # Return original on error

    def _remove_quote_markers(self, text: str) -> str:
        """Remove quote markers from text."""
        for marker in self.quote_markers:
            text = text.strip(marker)
        return text.strip()

    def _remove_attribution(self, text: str) -> str:
        """Remove attribution patterns from end of quotes."""
        for pattern in self.attribution_patterns:
            text = re.sub(pattern, "", text, flags=re.IGNORECASE)
        return text.strip()

    def _extract_game_context(self, text: str) -> str | None:
        """Extract game name from quote context."""
        for pattern in self.game_context_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                game_name = match.group(1).strip()
                if len(game_name) > 2:  # Ignore very short matches
                    return game_name
        return None


class ChatPreprocessor(BaseTextPreprocessor):
    """Preprocessor for live chat messages."""

    def __init__(self):
        super().__init__()

        # Twitch-specific patterns
        self.emote_patterns = [
            r"\b[A-Z][a-z]*[0-9]+\b",  # PogChamp1, Kappa123
            r"\b[a-z]+[A-Z][a-z]*\b",  # pogChamp, kekW
            r":[a-z_]+:",  # :kappa:, :pogchamp:
        ]

        # URL patterns
        self.url_pattern = r"https?://[^\s]+"

        # Command patterns
        self.command_patterns = [
            r"^![a-zA-Z]\w*",  # !command
            r"^[/@][a-zA-Z]\w*",  # @user, /command
        ]

        # Mention patterns
        self.mention_pattern = r"@(\w+)"

        # Common chat noise
        self.noise_patterns = [
            r"\b[0-9]+\b",  # isolated numbers
            r"\b[a-zA-Z]{1,2}\b",  # very short words (but preserve important ones)
        ]

        # Preserve important short words
        self.preserve_short_words = {"lol", "gg", "wp", "nt", "gl", "hf", "ez", "op", "af", "bf", "gf"}

    def preprocess(self, text_input: TextAnalysisInput) -> TextAnalysisInput:
        """Preprocess chat message.

        Args:
            text_input: Chat input to preprocess

        Returns:
            Preprocessed chat input
        """
        try:
            if text_input.source != TextSource.CHAT:
                logger.warning(
                    "ChatPreprocessor received non-chat input",
                    source=text_input.source.value,
                    input_id=text_input.input_id,
                )
                return text_input

            original_text = text_input.text
            processed_text = original_text

            # Extract and preserve mentions
            mentions = self._extract_mentions(processed_text)

            # Extract and preserve emotes
            emotes = self._extract_emotes(processed_text)

            # Remove URLs
            processed_text = self._remove_urls(processed_text)

            # Handle commands differently
            is_command = self._is_command(processed_text)
            if is_command:
                processed_text = self._process_command(processed_text)

            # Remove excessive punctuation
            processed_text = self._normalize_punctuation(processed_text)

            # Remove noise (but preserve important short words)
            processed_text = self._remove_noise(processed_text)

            # Unicode normalization
            processed_text = self._normalize_unicode(processed_text)

            # Clean whitespace
            processed_text = self._remove_excessive_whitespace(processed_text)

            # Preserve intentional repetition for emphasis
            processed_text = self._preserve_intentional_repetition(processed_text)

            # Update text input
            text_input.text = processed_text

            # Store extracted data in metadata
            if text_input.source_metadata:
                if mentions:
                    text_input.source_metadata.emotes.extend(mentions)
                if emotes:
                    text_input.source_metadata.emotes.extend(emotes)

            self.processed_count += 1

            logger.debug(
                "Preprocessed chat message",
                input_id=text_input.input_id,
                original_length=len(original_text),
                processed_length=len(processed_text),
                mentions_count=len(mentions),
                emotes_count=len(emotes),
                is_command=is_command,
            )

            return text_input

        except Exception as e:
            logger.error("Failed to preprocess chat message", input_id=text_input.input_id, error=str(e))
            self.error_count += 1
            return text_input

    def _extract_mentions(self, text: str) -> list[str]:
        """Extract username mentions from text."""
        mentions = re.findall(self.mention_pattern, text)
        return [mention.lower() for mention in mentions]

    def _extract_emotes(self, text: str) -> list[str]:
        """Extract emotes from text."""
        emotes = []
        for pattern in self.emote_patterns:
            matches = re.findall(pattern, text)
            emotes.extend(matches)
        return emotes

    def _remove_urls(self, text: str) -> str:
        """Remove URLs from text."""
        return re.sub(self.url_pattern, "[URL]", text)

    def _is_command(self, text: str) -> bool:
        """Check if text is a command."""
        return any(re.match(pattern, text.strip()) for pattern in self.command_patterns)

    def _process_command(self, text: str) -> str:
        """Process command text - preserve command but clean arguments."""
        parts = text.split(" ", 1)
        if len(parts) > 1:
            command, args = parts
            # Clean arguments but preserve command
            cleaned_args = self._remove_excessive_whitespace(args)
            return f"{command} {cleaned_args}"
        return text

    def _normalize_punctuation(self, text: str) -> str:
        """Normalize excessive punctuation."""
        # Reduce excessive punctuation but preserve some for emphasis
        text = re.sub(r"[!]{3,}", "!!!", text)
        text = re.sub(r"[?]{3,}", "???", text)
        text = re.sub(r"[.]{3,}", "...", text)
        return text

    def _remove_noise(self, text: str) -> str:
        """Remove noise patterns while preserving important short words."""
        words = text.split()
        filtered_words = []

        for word in words:
            word_lower = word.lower().strip(".,!?")

            # Preserve important short words
            if word_lower in self.preserve_short_words:
                filtered_words.append(word)
                continue

            # Remove isolated numbers unless they seem contextual
            if re.match(r"^\d+$", word) and len(word) < 4:
                continue

            # Remove very short meaningless words
            if len(word_lower) <= 2 and word_lower not in self.preserve_short_words:
                continue

            filtered_words.append(word)

        return " ".join(filtered_words)


class VoicePreprocessor(BaseTextPreprocessor):
    """Preprocessor for voice transcription text."""

    def __init__(self):
        super().__init__()

        # Transcription-specific artifacts
        self.filler_words = {"um", "uh", "ah", "er", "hmm", "uhm", "like", "you know", "i mean"}

        # Common transcription errors
        self.transcription_fixes = {
            " i ": " I ",
            " im ": " I'm ",
            " ive ": " I've ",
            " dont ": " don't ",
            " cant ": " can't ",
            " wont ": " won't ",
            " thats ": " that's ",
            " its ": " it's ",
            " hes ": " he's ",
            " shes ": " she's ",
            " theyre ": " they're ",
            " youre ": " you're ",
            " were ": " we're ",
        }

        # Sentence boundary markers
        self.sentence_enders = ".!?"

        # Word repetition pattern (transcription artifacts)
        self.repetition_pattern = r"\b(\w+)(?:\s+\1){2,}\b"

    def preprocess(self, text_input: TextAnalysisInput) -> TextAnalysisInput:
        """Preprocess voice transcription text.

        Args:
            text_input: Voice/transcription input to preprocess

        Returns:
            Preprocessed transcription input
        """
        try:
            if text_input.source not in [TextSource.TRANSCRIPTION, TextSource.VOICE]:
                logger.warning(
                    "VoicePreprocessor received non-voice input",
                    source=text_input.source.value,
                    input_id=text_input.input_id,
                )
                return text_input

            original_text = text_input.text
            processed_text = original_text.lower()  # Voice is typically lowercase

            # Remove excessive word repetitions (transcription artifacts)
            processed_text = self._fix_repetitions(processed_text)

            # Remove filler words
            processed_text = self._remove_fillers(processed_text)

            # Fix common transcription errors
            processed_text = self._fix_transcription_errors(processed_text)

            # Restore sentence capitalization
            processed_text = self._restore_capitalization(processed_text)

            # Unicode normalization
            processed_text = self._normalize_unicode(processed_text)

            # Clean whitespace
            processed_text = self._remove_excessive_whitespace(processed_text)

            # Calculate transcription confidence impact
            confidence_penalty = self._calculate_confidence_penalty(original_text, processed_text, text_input)

            # Update text input
            text_input.text = processed_text

            # Adjust processing hints based on cleanup
            if text_input.processing_hints and confidence_penalty > 0.2:
                text_input.processing_hints.priority -= 1  # Lower priority for heavily cleaned text

            self.processed_count += 1

            logger.debug(
                "Preprocessed voice transcription",
                input_id=text_input.input_id,
                original_length=len(original_text),
                processed_length=len(processed_text),
                confidence_penalty=confidence_penalty,
            )

            return text_input

        except Exception as e:
            logger.error("Failed to preprocess voice transcription", input_id=text_input.input_id, error=str(e))
            self.error_count += 1
            return text_input

    def _fix_repetitions(self, text: str) -> str:
        """Fix excessive word repetitions from transcription errors."""
        # Replace "word word word" with "word"
        return re.sub(self.repetition_pattern, r"\1", text)

    def _remove_fillers(self, text: str) -> str:
        """Remove filler words from transcription."""
        words = text.split()
        filtered_words = []

        for word in words:
            word_clean = word.strip(".,!?").lower()
            if word_clean not in self.filler_words:
                filtered_words.append(word)

        return " ".join(filtered_words)

    def _fix_transcription_errors(self, text: str) -> str:
        """Fix common transcription errors."""
        for error, correction in self.transcription_fixes.items():
            text = text.replace(error, correction)
        return text

    def _restore_capitalization(self, text: str) -> str:
        """Restore basic sentence capitalization."""
        if not text:
            return text

        # Capitalize first letter
        text = text[0].upper() + text[1:] if len(text) > 1 else text.upper()

        # Capitalize after sentence enders
        for ender in self.sentence_enders:
            text = re.sub(f"\\{ender}\\s+(\\w)", lambda m, e=ender: f"{e} {m.group(1).upper()}", text)

        return text

    def _calculate_confidence_penalty(self, original: str, processed: str, text_input: TextAnalysisInput) -> float:
        """Calculate confidence penalty based on amount of cleanup needed."""
        original_words = len(original.split())
        processed_words = len(processed.split())

        if original_words == 0:
            return 0.0

        # Word reduction ratio
        word_reduction = (original_words - processed_words) / original_words

        # Length reduction ratio
        length_reduction = (len(original) - len(processed)) / len(original)

        # Base transcription confidence
        base_confidence = 1.0
        if (
            text_input.source_metadata
            and hasattr(text_input.source_metadata, "confidence")
            and text_input.source_metadata.confidence
        ):
            base_confidence = text_input.source_metadata.confidence

        # Calculate penalty
        penalty = (word_reduction * 0.3) + (length_reduction * 0.2)

        # Higher penalty for already low-confidence transcriptions
        if base_confidence < 0.7:
            penalty *= 1.5

        return min(penalty, 1.0)


class PassThroughPreprocessor(BaseTextPreprocessor):
    """Pass-through preprocessor that only applies basic normalization."""

    def preprocess(self, text_input: TextAnalysisInput) -> TextAnalysisInput:
        """Apply minimal preprocessing.

        Args:
            text_input: Input to preprocess

        Returns:
            Lightly processed input
        """
        try:
            original_text = text_input.text
            processed_text = original_text

            # Basic unicode normalization
            processed_text = self._normalize_unicode(processed_text)

            # Clean excessive whitespace
            processed_text = self._remove_excessive_whitespace(processed_text)

            # Update text input
            text_input.text = processed_text

            self.processed_count += 1

            logger.debug(
                "Applied pass-through preprocessing",
                input_id=text_input.input_id,
                source=text_input.source.value,
                original_length=len(original_text),
                processed_length=len(processed_text),
            )

            return text_input

        except Exception as e:
            logger.error("Failed to apply pass-through preprocessing", input_id=text_input.input_id, error=str(e))
            self.error_count += 1
            return text_input


class TextPreprocessorFactory:
    """Factory for creating appropriate text preprocessors."""

    @staticmethod
    def get_preprocessor(source: TextSource) -> BaseTextPreprocessor:
        """Get the appropriate preprocessor for a text source.

        Args:
            source: Text source type

        Returns:
            Appropriate preprocessor instance
        """
        if source == TextSource.QUOTES:
            return QuotesPreprocessor()
        elif source == TextSource.CHAT:
            return ChatPreprocessor()
        elif source in [TextSource.TRANSCRIPTION, TextSource.VOICE]:
            return VoicePreprocessor()
        else:
            # Return a pass-through preprocessor for unknown sources
            logger.warning("Unknown text source, using pass-through preprocessor", source=source.value)
            return PassThroughPreprocessor()


# Convenience functions for external use


def preprocess_text_input(text_input: TextAnalysisInput) -> TextAnalysisInput:
    """Preprocess a text input using the appropriate preprocessor.

    Args:
        text_input: Input to preprocess

    Returns:
        Preprocessed input
    """
    preprocessor = TextPreprocessorFactory.get_preprocessor(text_input.source)
    return preprocessor.preprocess(text_input)


def preprocess_text_batch(text_inputs: list[TextAnalysisInput]) -> list[TextAnalysisInput]:
    """Preprocess a batch of text inputs.

    Args:
        text_inputs: List of inputs to preprocess

    Returns:
        List of preprocessed inputs
    """
    # Group by source for efficiency
    by_source: dict[TextSource, list[TextAnalysisInput]] = {}
    for text_input in text_inputs:
        if text_input.source not in by_source:
            by_source[text_input.source] = []
        by_source[text_input.source].append(text_input)

    # Process each group with appropriate preprocessor
    processed_inputs = []
    for source, inputs in by_source.items():
        preprocessor = TextPreprocessorFactory.get_preprocessor(source)
        for text_input in inputs:
            processed_input = preprocessor.preprocess(text_input)
            processed_inputs.append(processed_input)

    return processed_inputs
