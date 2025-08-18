"""Core vocabulary extraction algorithms for the text analysis pipeline.

This module implements the core algorithms for extracting community vocabulary
from text inputs using the standardized TextAnalysisInput schema.
"""

import re
from collections import Counter
from datetime import datetime

from .logger import get_logger
from .text_analysis_schema import TextAnalysisInput, TextAnalysisOutput

logger = get_logger(__name__)


class VocabularyExtractor:
    """Core vocabulary extraction algorithms for community text analysis."""

    def __init__(self):
        # Vocabulary patterns and scoring
        self.min_word_length = 3
        self.max_word_length = 50
        self.min_phrase_length = 2
        self.max_phrase_length = 8  # words

        # Common words to filter out
        self.common_words = {
            "the",
            "and",
            "or",
            "but",
            "is",
            "are",
            "was",
            "were",
            "have",
            "has",
            "had",
            "will",
            "would",
            "could",
            "should",
            "can",
            "may",
            "might",
            "must",
            "this",
            "that",
            "these",
            "those",
            "here",
            "there",
            "where",
            "when",
            "what",
            "who",
            "why",
            "how",
            "yes",
            "no",
            "not",
            "now",
            "then",
            "said",
            "say",
            "says",
            "get",
            "got",
            "go",
            "goes",
            "went",
            "come",
            "came",
            "see",
            "saw",
            "look",
            "looks",
            "like",
            "want",
            "wants",
            "need",
            "needs",
            "know",
            "knows",
            "think",
            "thinks",
            "good",
            "bad",
            "big",
            "small",
            "new",
            "old",
            "first",
            "last",
            "best",
            "better",
            "just",
            "only",
            "also",
            "even",
            "still",
            "more",
            "most",
            "much",
            "many",
            "some",
            "any",
            "all",
            "each",
            "every",
            "other",
            "another",
        }

        # Twitch/gaming specific common words
        self.gaming_common_words = {
            "game",
            "play",
            "player",
            "level",
            "boss",
            "win",
            "lose",
            "died",
            "kill",
            "chat",
            "stream",
            "streamer",
            "viewer",
            "follow",
            "sub",
            "subscriber",
            "raid",
            "host",
            "mod",
            "moderator",
            "emote",
            "kappa",
            "pogchamp",
            "yeah",
            "nope",
            "yep",
            "lol",
            "lmao",
            "rofl",
            "omg",
            "wtf",
            "gg",
        }

        # Pre-compiled patterns for potential vocabulary detection
        self.vocabulary_patterns = [
            # Repeated sequences (memes, catchphrases)
            re.compile(r"\b(\w+)\s+\1\b", re.IGNORECASE),  # word word
            re.compile(r"\b(\w+)\s+(\w+)\s+\1\s+\2\b", re.IGNORECASE),  # word1 word2 word1 word2
            # Capitalized sequences (proper nouns, emphasis)
            re.compile(r"\b[A-Z][A-Z]+\b"),  # ALL CAPS
            re.compile(r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b"),  # Title Case Phrases
            # Elongated words (emphasis)
            re.compile(r"\b\w*([a-z])\1{2,}\w*\b", re.IGNORECASE),  # loooong, noooo, etc
            # Special gaming patterns
            re.compile(r"\b\w*[0-9]+\w*\b"),  # words with numbers
            re.compile(r"\b\w+[xX]\w+\b"),  # xThing, Thingx patterns
        ]

        # Pre-compiled patterns for other operations
        self.word_pattern = re.compile(r"\b\w+\b")
        self.quoted_text_pattern = re.compile(r'"([^"]+)"')
        self.emphasized_pattern = re.compile(r"\b[A-Z]{2,}\b|\b\w*([a-z])\1{2,}\w*\b")
        self.long_words_pattern = re.compile(r"\b\w{6,}\b")
        self.consonant_cluster_pattern = re.compile(r"[bcdfghjklmnpqrstvwxyz]{3,}", re.IGNORECASE)
        self.mention_pattern = re.compile(r"@(\w+)")

    def extract_vocabulary(self, text_input: TextAnalysisInput) -> TextAnalysisOutput:
        """
        Extract vocabulary from a text input using various algorithms.

        Args:
            text_input: Standardized text input to analyze

        Returns:
            TextAnalysisOutput with vocabulary findings
        """
        start_time = datetime.utcnow()
        processing_start = start_time.timestamp() * 1000

        try:
            # Skip vocabulary extraction if requested
            if text_input.processing_hints and text_input.processing_hints.skip_vocabulary:
                logger.debug("Skipping vocabulary extraction per processing hints")
                return self._create_empty_output(text_input.input_id, start_time)

            # Extract potential vocabulary using multiple algorithms
            vocabulary_matches = self._find_known_vocabulary(text_input.text)
            potential_vocabulary = self._extract_potential_vocabulary(text_input.text)
            username_mentions = self._extract_username_mentions(text_input.text)

            # Calculate community engagement score
            community_score = self._calculate_community_score(
                len(vocabulary_matches), len(username_mentions), len(text_input.text)
            )

            # Check for pronunciation needs
            pronunciation_needed = self._identify_pronunciation_needs(text_input.text, username_mentions)

            processing_time = int((datetime.utcnow().timestamp() * 1000) - processing_start)

            output = TextAnalysisOutput(
                input_id=text_input.input_id,
                processed_at=start_time,
                vocabulary_matches=vocabulary_matches,
                potential_vocabulary=potential_vocabulary,
                community_score=community_score,
                username_mentions=username_mentions,
                pronunciation_needed=pronunciation_needed,
                processing_time_ms=processing_time,
                model_version="vocabulary_extractor_v1.0",
            )

            logger.debug(
                "Vocabulary extraction completed",
                input_id=text_input.input_id,
                vocabulary_count=len(vocabulary_matches),
                potential_count=len(potential_vocabulary),
                community_score=community_score,
                processing_time_ms=processing_time,
            )

            return output

        except Exception as e:
            processing_time = int((datetime.utcnow().timestamp() * 1000) - processing_start)
            logger.error(
                "Vocabulary extraction failed",
                input_id=text_input.input_id,
                error=str(e),
                processing_time_ms=processing_time,
            )

            return TextAnalysisOutput(
                input_id=text_input.input_id, processed_at=start_time, processing_time_ms=processing_time, error=str(e)
            )

    def _find_known_vocabulary(self, _text: str) -> list[str]:
        """Find usage of known community vocabulary in text."""
        # TODO: Integrate with community vocabulary database
        # For now, return empty list - will be implemented when integrated
        return []

    def _extract_potential_vocabulary(self, text: str) -> list[str]:
        """Extract potential new vocabulary from text using multiple algorithms."""
        potential = set()

        # Algorithm 1: Pattern-based extraction
        potential.update(self._extract_by_patterns(text))

        # Algorithm 2: Frequency-based extraction
        potential.update(self._extract_by_frequency(text))

        # Algorithm 3: Context-based extraction
        potential.update(self._extract_by_context(text))

        # Filter and score results
        filtered = self._filter_potential_vocabulary(list(potential), text)

        return filtered

    def _extract_by_patterns(self, text: str) -> list[str]:
        """Extract vocabulary using pre-compiled regex patterns."""
        matches = []

        for pattern in self.vocabulary_patterns:
            for match in pattern.finditer(text):
                candidate = match.group().strip().lower()
                if self._is_valid_vocabulary_candidate(candidate):
                    matches.append(candidate)

        return matches

    def _extract_by_frequency(self, text: str) -> list[str]:
        """Extract vocabulary based on word frequency and repetition."""
        words = self.word_pattern.findall(text.lower())
        word_counts = Counter(words)

        # Look for repeated words (might be emphasis or memes)
        repeated_words = [
            word for word, count in word_counts.items() if count > 1 and self._is_valid_vocabulary_candidate(word)
        ]

        # Look for unusual word combinations
        phrases = self._extract_phrases(text, 2, 4)  # 2-4 word phrases
        phrase_candidates = [phrase for phrase in phrases if self._is_potential_phrase(phrase)]

        return repeated_words + phrase_candidates

    def _extract_by_context(self, text: str) -> list[str]:
        """Extract vocabulary based on contextual clues."""
        candidates = []

        # Look for quoted text (might be references or catchphrases)
        quoted_text = self.quoted_text_pattern.findall(text)
        candidates.extend([quote.lower().strip() for quote in quoted_text])

        # Look for emphasized text (ALL CAPS, repeated letters)
        emphasized = self.emphasized_pattern.findall(text)
        candidates.extend([word.lower() for word in emphasized if isinstance(word, str)])

        return [c for c in candidates if self._is_valid_vocabulary_candidate(c)]

    def _extract_phrases(self, text: str, min_length: int, max_length: int) -> list[str]:
        """Extract multi-word phrases from text."""
        words = self.word_pattern.findall(text.lower())
        phrases = []

        for length in range(min_length, max_length + 1):
            for i in range(len(words) - length + 1):
                phrase = " ".join(words[i : i + length])
                if self._is_potential_phrase(phrase):
                    phrases.append(phrase)

        return phrases

    def _is_valid_vocabulary_candidate(self, candidate: str) -> bool:
        """Check if a candidate word is worth considering as vocabulary."""
        if not candidate or len(candidate) < self.min_word_length:
            return False

        if len(candidate) > self.max_word_length:
            return False

        # Filter out common words
        if candidate in self.common_words or candidate in self.gaming_common_words:
            return False

        # Must contain at least one letter
        return any(c.isalpha() for c in candidate)

    def _is_potential_phrase(self, phrase: str) -> bool:
        """Check if a phrase might be community vocabulary."""
        words = phrase.split()

        if len(words) < self.min_phrase_length or len(words) > self.max_phrase_length:
            return False

        # Must have at least one non-common word
        non_common_words = [
            word for word in words if word not in self.common_words and word not in self.gaming_common_words
        ]

        return len(non_common_words) > 0

    def _filter_potential_vocabulary(self, candidates: list[str], text: str) -> list[str]:
        """Filter and rank potential vocabulary candidates."""
        if not candidates:
            return []

        # Score each candidate
        scored_candidates = []
        for candidate in candidates:
            score = self._score_vocabulary_candidate(candidate, text)
            if score > 0.3:  # Minimum threshold
                scored_candidates.append((candidate, score))

        # Sort by score and return top candidates
        scored_candidates.sort(key=lambda x: x[1], reverse=True)
        return [candidate for candidate, score in scored_candidates[:10]]  # Top 10

    def _score_vocabulary_candidate(self, candidate: str, text: str) -> float:
        """Score a vocabulary candidate based on various factors."""
        score = 0.0

        # Length scoring (moderate length preferred)
        if 4 <= len(candidate) <= 12:
            score += 0.2
        elif len(candidate) < 4 or len(candidate) > 20:
            score -= 0.1

        # Frequency in text
        count = text.lower().count(candidate.lower())
        if count > 1:
            score += min(count * 0.1, 0.3)

        # Pattern bonuses
        if any(c.isupper() for c in candidate) and sum(1 for c in candidate if c.isupper()) >= 2:  # ALL CAPS
            score += 0.2

        # Check for repeated letters
        for i in range(len(candidate) - 2):
            if candidate[i] == candidate[i + 1] == candidate[i + 2] and candidate[i].isalpha():
                score += 0.2
                break

        if any(c.isdigit() for c in candidate):  # contains numbers
            score += 0.1

        # Penalize if it looks too much like a regular word
        if candidate.isalpha() and candidate.islower():
            score -= 0.1

        return max(0.0, min(1.0, score))

    def _extract_username_mentions(self, text: str) -> list[str]:
        """Extract potential username mentions from text."""
        mentions = []

        # @username patterns
        at_mentions = self.mention_pattern.findall(text)
        mentions.extend(at_mentions)

        # TODO: Check against known usernames from community database
        # For now, just return @mentions

        return list(set(mentions))  # Remove duplicates

    def _calculate_community_score(self, vocab_count: int, username_mentions: int, text_length: int) -> float:
        """Calculate community engagement score for text."""
        # Base score from vocabulary usage
        vocab_score = min(vocab_count * 0.3, 1.0)

        # Score from username mentions
        mention_score = min(username_mentions * 0.2, 0.5)

        # Length bonus for longer messages (more context)
        length_score = min(text_length / 200, 0.2)

        return min(vocab_score + mention_score + length_score, 1.0)

    def _identify_pronunciation_needs(self, text: str, username_mentions: list[str]) -> list[str]:
        """Identify words/names that might need pronunciation guidance."""
        pronunciation_needed = []

        # Check mentioned usernames for complexity
        for username in username_mentions:
            if self._needs_pronunciation_guide(username):
                pronunciation_needed.append(username)

        # Check for complex words in text
        words = self.long_words_pattern.findall(text)  # 6+ letter words
        for word in words:
            if self._needs_pronunciation_guide(word):
                pronunciation_needed.append(word)

        return list(set(pronunciation_needed))  # Remove duplicates

    def _needs_pronunciation_guide(self, word: str) -> bool:
        """Check if a word might need pronunciation guidance."""
        # Simple heuristics for pronunciation complexity
        if len(word) < 6:
            return False

        # Check for non-English patterns
        if self.consonant_cluster_pattern.search(word.lower()):
            return True

        # Check for uncommon letter combinations
        uncommon_patterns = ["zh", "kh", "gh", "ph", "th", "ch", "sh"]
        return any(pattern in word.lower() for pattern in uncommon_patterns)

    def _create_empty_output(self, input_id: str, processed_at: datetime) -> TextAnalysisOutput:
        """Create an empty output for skipped processing."""
        return TextAnalysisOutput(
            input_id=input_id,
            processed_at=processed_at,
            processing_time_ms=0,
            model_version="vocabulary_extractor_v1.0",
        )


# Factory function for easy instantiation
def create_vocabulary_extractor() -> VocabularyExtractor:
    """Create a new VocabularyExtractor instance."""
    return VocabularyExtractor()
