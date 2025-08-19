"""Community features for Seed service.

Provides username dictionary, pronunciation guidance, and vocabulary tracking
to enhance transcription accuracy and context analysis.
"""

import re
from datetime import datetime, timedelta

import aiohttp
from shared.config import get_config
from shared.logger import get_logger

logger = get_logger(__name__)


class CommunityManager:
    """Manages community features for improved transcription and context analysis."""

    def __init__(self, server_url: str | None = None):
        self.server_url = server_url or get_config().get("PHOENIX_SERVER_URL", "http://zelan:7175")
        self.session: aiohttp.ClientSession | None = None

        # In-memory caches for performance
        self._pronunciation_cache: dict[str, str] = {}
        self._vocabulary_cache: set[str] = set()
        self._alias_cache: dict[str, str] = {}
        self._member_cache: dict[str, dict] = {}

        # Cache update timestamps
        self._last_cache_update = datetime.utcnow() - timedelta(hours=1)
        self._cache_ttl = timedelta(minutes=30)

    async def __aenter__(self):
        """Async context manager entry."""
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30))
        await self._refresh_caches()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()

    async def process_chat_message(self, username: str, display_name: str, message: str) -> dict:
        """
        Process a chat message for community tracking.

        Args:
            username: Chat username
            display_name: Display name
            message: Chat message content

        Returns:
            Dictionary with processing results
        """
        try:
            # Ensure caches are fresh
            await self._ensure_fresh_cache()

            # Resolve username through aliases
            canonical_username = self._resolve_username(username)

            # Update community member activity
            await self._update_member_activity(canonical_username, display_name)

            # Detect vocabulary usage
            vocabulary_detected = self._detect_vocabulary_usage(message)

            # Extract potential new vocabulary
            potential_vocab = self._extract_potential_vocabulary(message)

            return {
                "canonical_username": canonical_username,
                "pronunciation_guide": self.get_pronunciation_guide(canonical_username),
                "vocabulary_detected": vocabulary_detected,
                "potential_vocabulary": potential_vocab,
                "processed_at": datetime.utcnow().isoformat(),
            }

        except Exception as e:
            logger.error(f"Error processing chat message: {e}", username=username, message_preview=message[:50])
            return {"error": str(e)}

    def get_pronunciation_guide(self, username: str) -> str | None:
        """
        Get pronunciation guide for a username.

        Args:
            username: Username to get pronunciation for

        Returns:
            Phonetic pronunciation guide or None
        """
        canonical = self._resolve_username(username)
        return self._pronunciation_cache.get(canonical.lower())

    def get_username_suggestions(self, partial_username: str, limit: int = 5) -> list[str]:
        """
        Get username suggestions for partial input.

        Args:
            partial_username: Partial username to match
            limit: Maximum suggestions to return

        Returns:
            List of suggested usernames
        """
        partial_lower = partial_username.lower()
        suggestions = []

        # Check direct matches in member cache
        for username in self._member_cache:
            if username.lower().startswith(partial_lower):
                suggestions.append(username)

        # Check alias matches
        for alias, canonical in self._alias_cache.items():
            if alias.lower().startswith(partial_lower):
                suggestions.append(canonical)

        # Remove duplicates and sort by relevance
        unique_suggestions = list(set(suggestions))
        unique_suggestions.sort(
            key=lambda x: (
                len(x),  # Prefer shorter matches
                x.lower().find(partial_lower),  # Prefer earlier matches
                x.lower(),  # Alphabetical fallback
            )
        )

        return unique_suggestions[:limit]

    def detect_community_context(self, message: str) -> dict:
        """
        Detect community-specific context in a message.

        Args:
            message: Message to analyze

        Returns:
            Dictionary with detected context
        """
        context = {"vocabulary_matches": [], "potential_references": [], "community_score": 0.0}

        # Check for known vocabulary
        message_lower = message.lower()
        for vocab_phrase in self._vocabulary_cache:
            if vocab_phrase in message_lower:
                context["vocabulary_matches"].append(vocab_phrase)

        # Check for username mentions
        usernames_mentioned = self._extract_username_mentions(message)
        context["usernames_mentioned"] = usernames_mentioned

        # Calculate community engagement score
        context["community_score"] = self._calculate_community_score(
            len(context["vocabulary_matches"]), len(usernames_mentioned), len(message)
        )

        return context

    async def add_pronunciation_override(self, username: str, phonetic: str, created_by: str = "system") -> bool:
        """
        Add a pronunciation override for a username.

        Args:
            username: Username to add pronunciation for
            phonetic: Phonetic pronunciation
            created_by: Who created this override

        Returns:
            True if successful, False otherwise
        """
        if not self.session:
            return False

        try:
            data = {"username": username, "phonetic": phonetic, "created_by": created_by, "confidence": 1.0}

            url = f"{self.server_url}/api/community/pronunciation"
            async with self.session.post(url, json=data) as response:
                if response.status == 201:
                    # Update cache
                    self._pronunciation_cache[username.lower()] = phonetic
                    logger.info(f"Added pronunciation override for {username}: {phonetic}")
                    return True
                else:
                    logger.error(f"Failed to add pronunciation override: HTTP {response.status}")
                    return False

        except Exception as e:
            logger.error(f"Error adding pronunciation override: {e}")
            return False

    async def add_vocabulary_entry(self, phrase: str, category: str, definition: str = "", context: str = "") -> bool:
        """
        Add a community vocabulary entry.

        Args:
            phrase: Vocabulary phrase
            category: Category (meme, inside_joke, etc.)
            definition: Definition of the phrase
            context: Context where it's used

        Returns:
            True if successful, False otherwise
        """
        if not self.session:
            return False

        try:
            data = {"phrase": phrase, "category": category, "definition": definition, "context": context}

            url = f"{self.server_url}/api/community/vocabulary"
            async with self.session.post(url, json=data) as response:
                if response.status == 201:
                    # Update cache
                    self._vocabulary_cache.add(phrase.lower())
                    logger.info(f"Added vocabulary entry: {phrase} ({category})")
                    return True
                else:
                    logger.error(f"Failed to add vocabulary entry: HTTP {response.status}")
                    return False

        except Exception as e:
            logger.error(f"Error adding vocabulary entry: {e}")
            return False

    # Private methods

    async def _ensure_fresh_cache(self):
        """Ensure caches are fresh, refresh if needed."""
        if datetime.utcnow() - self._last_cache_update > self._cache_ttl:
            await self._refresh_caches()

    async def _refresh_caches(self):
        """Refresh all caches from the server."""
        if not self.session:
            return

        try:
            # Refresh pronunciation cache
            await self._refresh_pronunciation_cache()

            # Refresh vocabulary cache
            await self._refresh_vocabulary_cache()

            # Refresh alias cache
            await self._refresh_alias_cache()

            # Refresh member cache
            await self._refresh_member_cache()

            self._last_cache_update = datetime.utcnow()
            logger.debug("Community caches refreshed successfully")

        except Exception as e:
            logger.error(f"Error refreshing caches: {e}")

    async def _refresh_pronunciation_cache(self):
        """Refresh pronunciation overrides cache."""
        try:
            url = f"{self.server_url}/api/community/pronunciation"
            async with self.session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    self._pronunciation_cache.clear()
                    for item in data.get("data", []):
                        self._pronunciation_cache[item["username"].lower()] = item["phonetic"]

        except Exception as e:
            logger.error(f"Error refreshing pronunciation cache: {e}")

    async def _refresh_vocabulary_cache(self):
        """Refresh vocabulary cache."""
        try:
            url = f"{self.server_url}/api/community/vocabulary"
            async with self.session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    self._vocabulary_cache.clear()
                    for item in data.get("data", []):
                        self._vocabulary_cache.add(item["phrase"].lower())

        except Exception as e:
            logger.error(f"Error refreshing vocabulary cache: {e}")

    async def _refresh_alias_cache(self):
        """Refresh username aliases cache."""
        try:
            url = f"{self.server_url}/api/community/aliases"
            async with self.session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    self._alias_cache.clear()
                    for item in data.get("data", []):
                        self._alias_cache[item["alias"].lower()] = item["canonical_username"]

        except Exception as e:
            logger.error(f"Error refreshing alias cache: {e}")

    async def _refresh_member_cache(self):
        """Refresh community members cache."""
        try:
            url = f"{self.server_url}/api/community/members"
            async with self.session.get(url, params={"limit": 1000}) as response:
                if response.status == 200:
                    data = await response.json()
                    self._member_cache.clear()
                    for item in data.get("data", []):
                        self._member_cache[item["username"].lower()] = item

        except Exception as e:
            logger.error(f"Error refreshing member cache: {e}")

    def _resolve_username(self, username: str) -> str:
        """Resolve username through aliases."""
        username_lower = username.lower()
        return self._alias_cache.get(username_lower, username)

    async def _update_member_activity(self, username: str, display_name: str):
        """Update member activity in the background."""
        if not self.session:
            return

        try:
            data = {"username": username, "display_name": display_name}

            url = f"{self.server_url}/api/community/members/activity"
            async with self.session.post(url, json=data) as response:
                if response.status not in [200, 201]:
                    logger.warning(f"Failed to update member activity: HTTP {response.status}")

        except Exception as e:
            logger.error(f"Error updating member activity: {e}")

    def _detect_vocabulary_usage(self, message: str) -> list[str]:
        """Detect usage of known vocabulary in message."""
        detected = []
        message_lower = message.lower()

        for vocab_phrase in self._vocabulary_cache:
            if vocab_phrase in message_lower:
                detected.append(vocab_phrase)

        return detected

    def _extract_potential_vocabulary(self, message: str) -> list[str]:
        """Extract potential new vocabulary from message."""
        # Simple extraction - look for repeated phrases, unusual words, etc.
        words = re.findall(r"\b\w{3,}\b", message.lower())

        # Filter for potentially interesting words
        potential = []
        for word in words:
            if len(word) >= 3 and word not in self._vocabulary_cache and not self._is_common_word(word):
                potential.append(word)

        return potential

    def _extract_username_mentions(self, message: str) -> list[str]:
        """Extract potential username mentions from message."""
        # Look for @mentions and partial username matches
        mentions = []

        # @username patterns
        at_mentions = re.findall(r"@(\w+)", message)
        mentions.extend(at_mentions)

        # Check for known usernames in message
        message_lower = message.lower()
        for username in self._member_cache:
            if username in message_lower:
                mentions.append(username)

        return list(set(mentions))  # Remove duplicates

    def _calculate_community_score(self, vocab_count: int, username_mentions: int, message_length: int) -> float:
        """Calculate community engagement score for a message."""
        # Base score from vocabulary usage
        vocab_score = min(vocab_count * 0.3, 1.0)

        # Score from username mentions
        mention_score = min(username_mentions * 0.2, 0.5)

        # Length bonus for longer messages
        length_score = min(message_length / 200, 0.2)

        return min(vocab_score + mention_score + length_score, 1.0)

    def _is_common_word(self, word: str) -> bool:
        """Check if word is too common to be interesting vocabulary."""
        common_words = {
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
        }
        return word.lower() in common_words


# Convenience functions for external use


async def process_chat_for_community(
    username: str, display_name: str, message: str, server_url: str | None = None
) -> dict:
    """
    Convenience function to process a single chat message.

    Args:
        username: Chat username
        display_name: Display name
        message: Message content
        server_url: Optional server URL

    Returns:
        Processing results dictionary
    """
    async with CommunityManager(server_url) as manager:
        return await manager.process_chat_message(username, display_name, message)


async def get_pronunciation_for_username(username: str, server_url: str | None = None) -> str | None:
    """
    Convenience function to get pronunciation for a username.

    Args:
        username: Username to get pronunciation for
        server_url: Optional server URL

    Returns:
        Phonetic pronunciation or None
    """
    async with CommunityManager(server_url) as manager:
        return manager.get_pronunciation_guide(username)
