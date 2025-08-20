"""RAG (Retrieval Augmented Generation) query handler for streaming data."""

import asyncio
import json
import re
from datetime import datetime
from typing import Any

import aiohttp
from aiohttp import web
from shared.logger import get_logger

from .community_api import CommunityVocabularyClient
from .context_client import ContextClient
from .rag_lms_client import RAGLMSClient

logger = get_logger(__name__)


class RAGHandler:
    """Handles natural language queries about streaming data using RAG pattern."""

    def __init__(
        self,
        context_client: ContextClient,
        server_url: str = "http://saya:7175",
        streamer_identity: str = "Avalonstar",
    ):
        """
        Initialize RAG handler with necessary clients.

        Args:
            context_client: Client for retrieving context data
            server_url: Phoenix server URL for additional data queries
            streamer_identity: The streamer's username/identity for context
        """
        self.context_client = context_client
        self.server_url = server_url
        self.streamer_identity = streamer_identity
        self.session: aiohttp.ClientSession | None = None
        logger.info(f"RAG Handler initialized with server_url: {server_url}, streamer: {streamer_identity}")
        # Configure RAG LMS client for exobrain experimentation
        # Default: Creative but controlled (good for personality understanding)
        self._rag_lms_client = RAGLMSClient(
            temperature=0.8,  # Creative enough for personality, not chaotic
            top_p=0.9,  # Diverse but focused token selection
        )
        self.rag_lms = None
        self._vocab_client = CommunityVocabularyClient(api_url=server_url)
        self.vocab_client = None

    async def __aenter__(self):
        """Async context manager entry."""
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30))
        # Initialize RAG LMS client
        self.rag_lms = await self._rag_lms_client.__aenter__()
        # Initialize vocabulary client
        self.vocab_client = await self._vocab_client.__aenter__()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()
        # Clean up RAG LMS client
        if self._rag_lms_client:
            await self._rag_lms_client.__aexit__(exc_type, exc_val, exc_tb)
        # Clean up vocabulary client
        if self._vocab_client:
            await self._vocab_client.__aexit__(exc_type, exc_val, exc_tb)

    async def query(self, question: str, time_window_hours: int | None = None) -> dict[str, Any]:
        """
        Process a natural language query about streaming data.

        Args:
            question: Natural language question from user
            time_window_hours: Optional time window for AI context pattern retrieval only.
                             Most data sources (chat, subscriptions, followers, raids, cheers)
                             are now unbounded bulk queries that return all available data.
                             Only AI context analysis respects this time window parameter.

        Returns:
            Dictionary containing the answer and supporting data
        """
        try:
            logger.info(f"Processing RAG query: {question[:100]}...")

            # Step 1: Retrieve relevant data based on the question
            try:
                retrieved_data = await self._retrieve_relevant_data(question, time_window_hours)
                logger.info(f"RAG retrieved data sources: {list(retrieved_data.get('raw_data', {}).keys())}")
            except Exception as e:
                logger.error(f"Error in _retrieve_relevant_data: {e}", exc_info=True)
                raise

            # Step 1.5: Enhance data with vocabulary context
            try:
                retrieved_data = await self._enhance_data_with_vocabulary(retrieved_data)
            except Exception as e:
                logger.error(f"Error enhancing vocabulary context: {e}", exc_info=True)
                # Continue without vocabulary context rather than failing

            # Step 2: Generate AI response using retrieved data as context
            try:
                response = await self._generate_response(question, retrieved_data)
            except Exception as e:
                logger.error(f"Error in _generate_response: {e}", exc_info=True)
                raise

            return {
                "success": True,
                "question": question,
                "answer": response.get("answer", "Unable to generate response"),
                "confidence": response.get("confidence", 0.0),
                "data_summary": response.get("data_summary"),
                "sources": retrieved_data.get("sources", []),
                "time_window_hours": time_window_hours,
                "timestamp": datetime.utcnow().isoformat(),
            }

        except Exception as e:
            logger.error(f"Error processing RAG query: {e}")
            return {
                "success": False,
                "question": question,
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat(),
            }

    async def _retrieve_relevant_data(self, question: str, time_window_hours: int | None) -> dict[str, Any]:
        """
        Retrieve relevant data based on the question using stream sessions instead of time windows.

        This function analyzes the question to determine which stream session(s) the user is asking about,
        then retrieves all data for those specific sessions:
        - Detects session intent ("current stream", "last stream", "that stream where...")
        - Gets appropriate session data (chat, follows, subs, game changes)
        - Returns session-contextualized data instead of arbitrary time windows

        The time_window_hours parameter is now ignored - sessions provide natural boundaries.
        """
        retrieved_data = {"sources": [], "raw_data": {}}

        try:
            # Step 1: Detect which session(s) the user is asking about
            session_intent = await self._detect_session_from_query(question)
            logger.info(f"RAG detected session intent: {session_intent}")

            # Step 2: Get available stream sessions
            all_sessions = await self._get_stream_sessions()
            if not all_sessions:
                logger.warning("No stream sessions found")
                # Fallback to legacy time-based approach for this query
                return await self._retrieve_legacy_data(question, time_window_hours)

            # Step 3: Select appropriate session(s) based on intent
            target_sessions = []

            if session_intent == "current":
                # Find ongoing session or most recent completed session
                live_sessions = [s for s in all_sessions if s["status"] == "live"]
                if live_sessions:
                    target_sessions = [live_sessions[0]]  # Should only be one live session
                elif all_sessions:
                    target_sessions = [all_sessions[0]]  # Most recent completed session

            elif session_intent == "last":
                # Find most recent completed session (skip live session if exists)
                completed_sessions = [s for s in all_sessions if s["status"] == "completed"]
                if completed_sessions:
                    target_sessions = [completed_sessions[0]]  # Most recent completed

            elif session_intent == "specific":
                # For specific queries like "when I was playing X", we may need multiple sessions
                # For now, use current approach but this could be enhanced to search by game
                if all_sessions:
                    target_sessions = all_sessions[:2]  # Last 2 sessions as context

            if not target_sessions:
                logger.warning(f"No sessions found for intent: {session_intent}")
                return await self._retrieve_legacy_data(question, time_window_hours)

            # Step 4: Get comprehensive data for selected session(s)
            session_data_tasks = []
            for session in target_sessions:
                session_data_tasks.append(self._get_session_data(session))

            session_results = await asyncio.gather(*session_data_tasks, return_exceptions=True)

            # Step 5: Combine session data into standardized format
            combined_chat_messages = []
            combined_follows = []
            combined_subs = []
            combined_game_changes = []
            session_summaries = []

            for i, result in enumerate(session_results):
                if isinstance(result, Exception):
                    logger.error(f"Session data retrieval failed for session {i}: {result}")
                    continue

                combined_chat_messages.extend(result.get("chat_messages", []))
                combined_follows.extend(result.get("follows", []))
                combined_subs.extend(result.get("subscriptions", []))
                combined_game_changes.extend(result.get("game_changes", []))

                session_info = result.get("session_info", {})
                summary = {
                    "session_id": session_info.get("session_id"),
                    "status": session_info.get("status"),
                    "start_time": session_info.get("start_time").isoformat()
                    if session_info.get("start_time")
                    else None,
                    "end_time": session_info.get("end_time").isoformat() if session_info.get("end_time") else None,
                    "message_count": result.get("message_count", 0),
                    "unique_chatters": result.get("unique_chatters", 0),
                    "game_changes": len(result.get("game_changes", [])),
                }
                session_summaries.append(summary)

            # Sort by timestamp (most recent first)
            combined_chat_messages.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
            combined_follows.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
            combined_subs.sort(key=lambda x: x.get("timestamp", ""), reverse=True)

            # Store in standardized format for compatibility with response generation
            retrieved_data["raw_data"]["chat_messages"] = combined_chat_messages
            retrieved_data["raw_data"]["follower_events"] = combined_follows
            retrieved_data["raw_data"]["subscription_events"] = combined_subs
            retrieved_data["raw_data"]["stream_sessions"] = session_summaries
            retrieved_data["raw_data"]["game_changes"] = combined_game_changes

            retrieved_data["sources"] = [
                "stream_sessions",
                "chat_messages",
                "follower_events",
                "subscription_events",
                "game_changes",
            ]

            # Always add basic stats for context
            try:
                stats = await self._get_activity_stats()
                retrieved_data["raw_data"]["activity_stats"] = stats
                retrieved_data["sources"].append("activity_stats")
            except Exception as e:
                logger.error(f"Error getting activity stats: {e}")

            logger.info(
                f"RAG session-based retrieval: {len(combined_chat_messages)} messages, "
                f"{len(combined_follows)} follows, {len(combined_subs)} subs across {len(target_sessions)} sessions"
            )

            return retrieved_data

        except Exception as e:
            logger.error(f"Error in session-based data retrieval: {e}")
            # Fallback to legacy approach
            return await self._retrieve_legacy_data(question, time_window_hours)

    async def _retrieve_legacy_data(self, question: str, time_window_hours: int | None = None) -> dict[str, Any]:  # noqa: ARG002
        """
        Legacy time-window based data retrieval for fallback cases.
        This preserves the old logic when session-based retrieval fails.
        """
        question_lower = question.lower()
        retrieved_data = {"sources": [], "raw_data": {}}

        # Determine what data to retrieve based on keywords
        queries_to_run = []

        # Check for subscriber-related queries
        if any(word in question_lower for word in ["sub", "subscriber", "subscription", "resub", "gift"]):
            queries_to_run.append(self._get_subscription_data())
            retrieved_data["sources"].append("subscription_events")

        # Check for follower-related queries
        if any(word in question_lower for word in ["follow", "follower", "new viewer"]):
            queries_to_run.append(self._get_follower_data())
            retrieved_data["sources"].append("follower_events")

        # Check for chat/message queries
        if any(word in question_lower for word in ["chat", "message", "said", "talking", "conversation"]):
            queries_to_run.append(self._get_chat_data())
            retrieved_data["sources"].append("chat_messages")

        # Check for game/stream content queries
        if any(word in question_lower for word in ["game", "playing", "stream", "title", "category"]):
            queries_to_run.append(self._get_stream_info())
            retrieved_data["sources"].append("stream_info")

        # Always get basic stats for context
        queries_to_run.append(self._get_activity_stats())
        retrieved_data["sources"].append("activity_stats")

        # Run all queries in parallel
        results = await asyncio.gather(*queries_to_run, return_exceptions=True)

        # Process results - match them with the correct sources
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(f"Query {i} failed: {result}")
            elif result:
                # Map results back to the correct source names
                source = retrieved_data["sources"][i] if i < len(retrieved_data["sources"]) else f"query_{i}"
                retrieved_data["raw_data"][source] = result

        return retrieved_data

    async def _enhance_data_with_vocabulary(self, retrieved_data: dict[str, Any]) -> dict[str, Any]:
        """
        Enhance retrieved data with vocabulary context for better AI understanding.

        This method:
        1. Extracts terms from chat messages and other data
        2. Looks up definitions for community vocabulary
        3. Adds vocabulary context to help AI understand stream lingo
        """
        if not self.vocab_client:
            return retrieved_data

        try:
            terms_to_lookup = set()

            # Extract terms from chat messages
            if "chat_messages" in retrieved_data.get("raw_data", {}):
                chat_data = retrieved_data["raw_data"]["chat_messages"]
                for msg in chat_data:  # Process ALL messages for full context
                    if isinstance(msg, dict) and "data" in msg:
                        data = msg["data"]
                        if isinstance(data, dict) and "message" in data:
                            message_text = ""
                            if isinstance(data["message"], dict):
                                message_text = data["message"].get("text", "")
                            else:
                                message_text = str(data["message"])

                            # Extract potential vocabulary terms (3+ chars, not common words)
                            words = re.findall(r"\b\w{3,}\b", message_text.lower())
                            for word in words:
                                if not self._is_common_word(word):
                                    terms_to_lookup.add(word)

                            # Extract channel emotes (prefixSUFFIX/prefixSuffix pattern)
                            emotes = self._extract_emotes_from_text(message_text)
                            for emote in emotes:
                                terms_to_lookup.add(emote)

            # Look up vocabulary definitions
            vocab_definitions = {}
            for term in list(terms_to_lookup):  # Process ALL terms for full context
                results = await self.vocab_client.search_vocabulary(term, limit=1)
                if results:
                    vocab_entry = results[0]
                    vocab_definitions[term] = {
                        "phrase": vocab_entry.get("phrase"),
                        "category": vocab_entry.get("category"),
                        "definition": vocab_entry.get("definition"),
                        "usage_count": vocab_entry.get("usage_count", 0),
                    }

            # Get popular community vocabulary for general context
            popular_vocab = await self.vocab_client.get_popular_vocabulary(limit=10)

            # Add vocabulary context to retrieved data
            retrieved_data["vocabulary_context"] = {
                "term_definitions": vocab_definitions,
                "popular_vocabulary": popular_vocab,
                "terms_searched": len(terms_to_lookup),
            }

            logger.info(
                f"Enhanced data with {len(vocab_definitions)} vocabulary definitions and {len(popular_vocab)} popular terms"
            )

        except Exception as e:
            logger.error(f"Error enhancing data with vocabulary context: {e}")

        return retrieved_data

    def _extract_emotes_from_text(self, text: str) -> list[str]:
        """Extract channel emotes from text using prefix pattern matching."""
        if not text:
            return []

        # Pattern for channel emotes: prefixSUFFIX or prefixSuffix
        # Common prefixes include: avalon, bard, pog, kappa, etc.
        # Must be at least 5 chars total (3 char prefix + 2 char suffix minimum)
        emote_pattern = r"\b([a-zA-Z]{3,})([A-Z][A-Z0-9]*|[A-Z][a-z][a-zA-Z0-9]*)\b"

        emotes = []
        matches = re.findall(emote_pattern, text)

        for prefix, suffix in matches:
            emote_name = prefix + suffix
            # Filter out obvious non-emotes (common words, URLs, etc.)
            if (
                len(emote_name) >= 5
                and not self._is_common_word(emote_name.lower())
                and not emote_name.lower().startswith(("http", "www", "com"))
            ):
                emotes.append(emote_name)

        return emotes

    def _is_common_word(self, word: str) -> bool:
        """Check if word is too common to look up in vocabulary."""
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
        }
        return word.lower() in common_words

    async def _generate_response(self, question: str, retrieved_data: dict[str, Any]) -> dict[str, Any]:
        """
        Generate an AI response using the retrieved data as context.
        """
        # Build context for LMS
        context_parts = []

        # Add stream flow context first
        stream_flow_context = self._build_stream_flow_context(retrieved_data)
        if stream_flow_context:
            context_parts.append(stream_flow_context)

        # Add community vocabulary context
        vocab_context = self._build_vocabulary_context(retrieved_data)
        if vocab_context:
            context_parts.append(vocab_context)

        # Add session context if available (new session-based approach)
        if "stream_sessions" in retrieved_data.get("raw_data", {}):
            sessions = retrieved_data["raw_data"]["stream_sessions"]
            if sessions:
                session_context = self._build_session_context(sessions)
                context_parts.append(session_context)

        # Add activity stats if available (fallback/legacy approach)
        elif "activity_stats" in retrieved_data.get("raw_data", {}):
            stats = retrieved_data["raw_data"]["activity_stats"]
            context_parts.append(
                f"Stream Activity Summary:\n"
                f"- Total events: {stats.get('total_events', 0)}\n"
                f"- Unique users: {stats.get('unique_users', 0)}\n"
                f"- Chat messages: {stats.get('chat_messages', 0)}\n"
                f"- New followers: {stats.get('follows', 0)}\n"
                f"- Subscriptions: {stats.get('subscriptions', 0)}\n"
                f"- Cheers: {stats.get('cheers', 0)}"
            )

        # Add game context if we have chat messages
        game_context = await self._build_game_context(retrieved_data)
        if game_context:
            context_parts.append(game_context)

        # Add specific data based on what was retrieved
        for source, data in retrieved_data.get("raw_data", {}).items():
            if source == "subscription_events" and data:
                context_parts.append(f"\nSubscription Data:\n{self._format_subscription_data(data)}")
            elif source == "follower_events" and data:
                context_parts.append(f"\nFollower Data:\n{self._format_follower_data(data)}")
            elif source == "chat_messages" and data:
                context_parts.append(f"\nRecent Chat Activity:\n{self._format_chat_data(data)}")
            elif source == "stream_info" and data:
                context_parts.append(f"\nStream Information:\n{self._format_stream_info(data)}")
            elif source == "ai_context_analysis" and data:
                context_parts.append(f"\nAI Context Analysis:\n{self._format_context_analysis(data)}")
            elif source == "context_search" and data:
                context_parts.append(f"\nRelevant Transcript Segments:\n{self._format_context_search(data)}")

        full_context = "\n".join(context_parts)

        # Build prompt for LMS with structured response guidance
        prompt = f"""You are answering questions about {self.streamer_identity}'s Twitch stream based on real data.

Question: "{question}"

Available Data:
{full_context}

CRITICAL IDENTITY CONTEXT: The person asking this question IS {self.streamer_identity}, the streamer themselves. They are asking about THEIR OWN stream. When they say "my chat" they mean their channel's chat. When you see "{self.streamer_identity}" in the data, that refers to the person asking the question, not a separate user.

Instructions for your structured response:
1. **answer**: Provide a direct, concise answer (2-3 sentences max) using ONLY the provided data
2. **confidence**: Rate your confidence 0.0-1.0 based on data completeness and clarity
3. **reasoning**: Brief explanation of how you derived the answer from the data
4. **response_type**: Choose from:
   - "factual": Answering with specific data/numbers
   - "creative": Providing suggestions or personality-based insights
   - "clarification": Need more information or data is ambiguous
   - "insufficient_data": Not enough data to answer properly
5. **suggestions**: (Optional) For creative responses, provide follow-up ideas or "what if" scenarios

Guidelines:
- The person asking IS {self.streamer_identity}, so respond accordingly (use "your chat", "your stream", etc.)
- When asked "What happened in my chat?", focus on CONTENT and TOPICS, not just message counts - what were people talking about, what emotes were used, what was the mood?
- Be precise with numbers, usernames, and facts from the data
- Use Community Vocabulary Context to understand stream lingo, emotes, and inside jokes
- Use Stream Flow Context to understand whether events are from live streaming or offline periods
- Channel emotes follow the pattern prefixSUFFIX/prefixSuffix (e.g., avalonSTARWHEE, bardLove) - recognize these as expressions of emotion/reaction, not regular words
- Remember: "Stream offline" means the stream ended normally - this is NOT a problem or error
- When mentioning community terms or emotes, use their proper definitions if provided
- For creative questions, think about stream personality and community dynamics

Respond using the structured format."""

        try:
            # Use RAG LMS client to generate structured response
            if self.rag_lms:
                response = await self.rag_lms.generate_response(prompt)

                if response:
                    return {
                        "answer": response["answer"],
                        "confidence": response["confidence"],
                        "data_summary": f"AI analysis of {len(retrieved_data.get('sources', []))} data sources",
                        "response_type": response["response_type"],
                        "reasoning": response["reasoning"],
                        "suggestions": response.get("suggestions"),
                    }
                else:
                    logger.warning("RAG LMS client returned empty response")
                    return self._generate_fallback_response(question, retrieved_data)
            else:
                logger.error("RAG LMS client not available")
                return self._generate_fallback_response(question, retrieved_data)

        except Exception as e:
            logger.error(f"Error generating RAG LMS response: {e}")
            return self._generate_fallback_response(question, retrieved_data)

    def _build_stream_flow_context(self, retrieved_data: dict[str, Any]) -> str:
        """
        Build context about stream flow lifecycle to help AI understand stream states.
        """
        context_lines = ["Stream Flow Context:"]

        # Check current stream status
        stream_info = retrieved_data.get("raw_data", {}).get("stream_info", {})
        if stream_info:
            stream = stream_info.get("stream", {})
            if stream.get("type") == "live":
                context_lines.append("- Stream is currently LIVE (data represents active streaming period)")
                context_lines.append("- Recent events occur during active streaming")
            else:
                context_lines.append("- Stream is currently OFFLINE (most recent event: stream ended)")
                context_lines.append("- Events from time window include both streaming and offline periods")
                context_lines.append("- IMPORTANT: 'Stream offline' is normal end-of-stream, NOT a problem")
                context_lines.append("- Pre-stream setup → Live streaming → Post-stream analysis is normal flow")
        else:
            context_lines.append(
                "- Stream status unknown - treat recent events as potentially from different stream states"
            )

        # Add context about typical stream lifecycle
        context_lines.append("- Stream Lifecycle: Pre-stream (setup) → Live (active) → Post-stream (offline)")
        context_lines.append("- Events from different lifecycle phases are all valid data points")

        return "\n".join(context_lines)

    def _build_vocabulary_context(self, retrieved_data: dict[str, Any]) -> str:
        """
        Build context about community vocabulary to help AI understand stream lingo.
        """
        vocab_data = retrieved_data.get("vocabulary_context", {})
        if not vocab_data:
            return ""

        context_lines = ["Community Vocabulary Context:"]

        # Add definitions for terms found in the data
        term_definitions = vocab_data.get("term_definitions", {})
        if term_definitions:
            context_lines.append("- Term Definitions (stream lingo/community terms):")
            for term, info in term_definitions.items():
                definition = info.get("definition", "")
                category = info.get("category", "unknown")
                if definition:
                    context_lines.append(f"  • '{term}' ({category}): {definition}")
                else:
                    context_lines.append(f"  • '{term}': recognized {category} in this community")

        # Add popular community vocabulary for general context
        popular_vocab = vocab_data.get("popular_vocabulary", [])
        if popular_vocab and len(popular_vocab) > 0:
            context_lines.append("- Popular Community Terms:")
            for vocab in popular_vocab[:5]:  # Top 5
                phrase = vocab.get("phrase", "")
                definition = vocab.get("definition", "")
                category = vocab.get("category", "")
                if phrase and definition:
                    context_lines.append(f"  • '{phrase}' ({category}): {definition}")
                elif phrase:
                    context_lines.append(f"  • '{phrase}': community {category}")

        context_lines.append("- Use these definitions when interpreting chat messages and user interactions")

        return "\n".join(context_lines)

    def _generate_fallback_response(self, _question: str, retrieved_data: dict[str, Any]) -> dict[str, Any]:
        """Generate a basic response when LMS is unavailable."""
        raw_data = retrieved_data.get("raw_data", {})

        # Try to provide basic answers for common queries
        if "subscription_events" in raw_data:
            subs = raw_data["subscription_events"]
            if subs:
                return {
                    "answer": f"Found {len(subs)} subscription events in the requested time period.",
                    "confidence": 0.5,
                    "data_summary": "Subscription event data",
                }

        if "activity_stats" in raw_data:
            stats = raw_data["activity_stats"]
            return {
                "answer": f"In the requested time period: {stats.get('chat_messages', 0)} chat messages, "
                f"{stats.get('follows', 0)} new followers, {stats.get('subscriptions', 0)} subscriptions.",
                "confidence": 0.6,
                "data_summary": "Activity statistics",
            }

        return {
            "answer": "I have the data but need the AI model to provide a detailed answer. Please try again.",
            "confidence": 0.0,
            "data_summary": f"Retrieved {len(raw_data)} data sources",
        }

    async def _get_stream_sessions(self) -> list[dict]:
        """Get stream sessions (pairs of stream.online/stream.offline events)."""
        if not self.session:
            return []

        try:
            # Get stream online events
            online_url = f"{self.server_url}/api/activity/events"
            online_params = {"event_type": "stream.online"}

            # Get stream offline events
            offline_url = f"{self.server_url}/api/activity/events"
            offline_params = {"event_type": "stream.offline"}

            online_events = []
            offline_events = []

            async with self.session.get(online_url, params=online_params) as response:
                if response.status == 200:
                    data = await response.json()
                    online_events = data.get("data", {}).get("events", [])

            async with self.session.get(offline_url, params=offline_params) as response:
                if response.status == 200:
                    data = await response.json()
                    offline_events = data.get("data", {}).get("events", [])

            # Parse and sort events by timestamp
            online_parsed = []
            for event in online_events:
                try:
                    event_time = datetime.fromisoformat(event["timestamp"])
                    online_parsed.append((event_time, event))
                except ValueError:
                    continue

            offline_parsed = []
            for event in offline_events:
                try:
                    event_time = datetime.fromisoformat(event["timestamp"])
                    offline_parsed.append((event_time, event))
                except ValueError:
                    continue

            # Sort by timestamp (most recent first)
            online_parsed.sort(key=lambda x: x[0], reverse=True)
            offline_parsed.sort(key=lambda x: x[0], reverse=True)

            # Create sessions by pairing online/offline events
            sessions = []

            # If we have an ongoing stream (latest online > latest offline), create current session
            if online_parsed and (not offline_parsed or online_parsed[0][0] > offline_parsed[0][0]):
                current_session = {
                    "session_id": f"session_{int(online_parsed[0][0].timestamp())}",
                    "start_time": online_parsed[0][0],
                    "end_time": None,  # Ongoing
                    "start_event": online_parsed[0][1],
                    "end_event": None,
                    "status": "live",
                }
                sessions.append(current_session)

            # Match offline events to preceding online events for completed sessions
            used_online_indices = set()
            if online_parsed and offline_parsed and online_parsed[0][0] > offline_parsed[0][0]:
                # Skip the first online event (current session)
                used_online_indices.add(0)

            for offline_time, offline_event in offline_parsed:
                # Find the most recent online event before this offline event
                for i, (online_time, online_event) in enumerate(online_parsed):
                    if i in used_online_indices:
                        continue
                    if online_time < offline_time:
                        session = {
                            "session_id": f"session_{int(online_time.timestamp())}",
                            "start_time": online_time,
                            "end_time": offline_time,
                            "start_event": online_event,
                            "end_event": offline_event,
                            "status": "completed",
                        }
                        sessions.append(session)
                        used_online_indices.add(i)
                        break

            logger.info(f"RAG Handler: Found {len(sessions)} stream sessions")
            return sessions

        except Exception as e:
            logger.error(f"Error fetching stream sessions: {e}")
            return []

    async def _get_session_data(self, session: dict) -> dict:
        """Get all data for a specific stream session."""
        if not self.session:
            return {}

        start_time = session["start_time"]
        end_time = session.get("end_time")  # None for ongoing sessions

        try:
            # Get chat messages for this session
            chat_messages = await self._get_chat_data_for_session(start_time, end_time)

            # Get game changes during this session
            game_changes = await self._get_game_changes_for_session(start_time, end_time)

            # Get follows/subs during this session
            follows = await self._get_follows_for_session(start_time, end_time)
            subs = await self._get_subs_for_session(start_time, end_time)

            return {
                "session_info": session,
                "chat_messages": chat_messages,
                "game_changes": game_changes,
                "follows": follows,
                "subscriptions": subs,
                "message_count": len(chat_messages),
                "unique_chatters": len({msg.get("user_login", "") for msg in chat_messages if msg.get("user_login")}),
            }

        except Exception as e:
            logger.error(f"Error getting session data: {e}")
            return {"session_info": session}

    async def _get_chat_data_for_session(self, start_time: datetime, end_time: datetime | None) -> list[dict]:
        """Get chat messages within session timeframe."""
        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.chat.message"}

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    all_messages = data.get("data", {}).get("events", [])

                    # Filter messages within session timeframe
                    session_messages = []
                    for msg in all_messages:
                        try:
                            msg_time = datetime.fromisoformat(msg["timestamp"])
                            if msg_time >= start_time and (end_time is None or msg_time <= end_time):
                                session_messages.append(msg)
                        except ValueError:
                            continue

                    return session_messages
        except Exception as e:
            logger.error(f"Error getting chat data for session: {e}")

        return []

    async def _get_game_changes_for_session(self, start_time: datetime, end_time: datetime | None) -> list[dict]:
        """Get game/category changes within session timeframe."""
        try:
            raw_events = await self._get_channel_update_data()

            session_changes = []
            for event in raw_events:
                try:
                    event_time = datetime.fromisoformat(event["timestamp"])
                    if event_time >= start_time and (end_time is None or event_time <= end_time):
                        session_changes.append(event)
                except ValueError:
                    continue

            return session_changes
        except Exception as e:
            logger.error(f"Error getting game changes for session: {e}")

        return []

    async def _get_follows_for_session(self, start_time: datetime, end_time: datetime | None) -> list[dict]:
        """Get follows within session timeframe."""
        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.follow"}

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    all_follows = data.get("data", {}).get("events", [])

                    session_follows = []
                    for follow in all_follows:
                        try:
                            follow_time = datetime.fromisoformat(follow["timestamp"])
                            if follow_time >= start_time and (end_time is None or follow_time <= end_time):
                                session_follows.append(follow)
                        except ValueError:
                            continue

                    return session_follows
        except Exception as e:
            logger.error(f"Error getting follows for session: {e}")

        return []

    async def _get_subs_for_session(self, start_time: datetime, end_time: datetime | None) -> list[dict]:
        """Get subscriptions within session timeframe."""
        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.subscribe"}

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    all_subs = data.get("data", {}).get("events", [])

                    session_subs = []
                    for sub in all_subs:
                        try:
                            sub_time = datetime.fromisoformat(sub["timestamp"])
                            if sub_time >= start_time and (end_time is None or sub_time <= end_time):
                                session_subs.append(sub)
                        except ValueError:
                            continue

                    return session_subs
        except Exception as e:
            logger.error(f"Error getting subs for session: {e}")

        return []

    async def _detect_session_from_query(self, question: str) -> str:
        """Detect which session the user is asking about."""
        question_lower = question.lower()

        # Current/ongoing session indicators
        current_indicators = [
            "this stream",
            "today's stream",
            "current stream",
            "now",
            "today",
            "this session",
            "currently",
            "right now",
            "what's happening",
        ]

        # Last/previous session indicators
        previous_indicators = [
            "last stream",
            "previous stream",
            "my last stream",
            "yesterday",
            "before",
            "earlier",
            "the stream before",
        ]

        # Specific session indicators
        specific_indicators = ["when I was playing", "during my", "while I was", "that stream where"]

        for indicator in current_indicators:
            if indicator in question_lower:
                return "current"

        for indicator in previous_indicators:
            if indicator in question_lower:
                return "last"

        for indicator in specific_indicators:
            if indicator in question_lower:
                return "specific"

        # Default to current session if unclear
        return "current"

    async def _get_subscription_data(self) -> list[dict]:
        """Get all subscription events."""
        if not self.session:
            return []

        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.subscribe"}
            logger.info(f"RAG Handler fetching subscription data from firehose API: {url} with params: {params}")

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    events = data.get("data", {}).get("events", [])
                    logger.info(f"RAG Handler subscription: Got {len(events)} events from firehose API")
                    return events

        except Exception as e:
            logger.error(f"Error fetching subscription data: {e}")

        return []

    async def _get_follower_data(self) -> list[dict]:
        """Get all follower events."""
        if not self.session:
            return []

        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.follow"}
            logger.info(f"RAG Handler fetching follower data from firehose API: {url} with params: {params}")

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    events = data.get("data", {}).get("events", [])
                    logger.info(f"RAG Handler follower: Got {len(events)} events from firehose API")
                    return events

        except Exception as e:
            logger.error(f"Error fetching follower data: {e}")

        return []

    async def _get_chat_data(self) -> list[dict]:
        """Get all chat messages."""
        if not self.session:
            return []

        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.chat.message"}
            logger.info(f"RAG Handler fetching chat data from firehose API: {url} with params: {params}")

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    events = data.get("data", {}).get("events", [])
                    logger.info(f"RAG Handler chat: Got {len(events)} events from firehose API")
                    return events

        except Exception as e:
            logger.error(f"Error fetching chat data: {e}")

        return []

    async def _get_stream_info(self) -> dict:
        """Get current stream information."""
        if not self.session:
            return {}

        try:
            # Get Twitch status which includes stream info
            url = f"{self.server_url}/api/twitch/status"

            async with self.session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    return data.get("data", {})

        except Exception as e:
            logger.error(f"Error fetching stream info: {e}")

        return {}

    async def _get_raid_data(self) -> list[dict]:
        """Get all raid events."""
        if not self.session:
            return []

        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.raid"}
            logger.info(f"RAG Handler fetching raid data from firehose API: {url} with params: {params}")

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    events = data.get("data", {}).get("events", [])
                    logger.info(f"RAG Handler raid: Got {len(events)} events from firehose API")
                    return events

        except Exception as e:
            logger.error(f"Error fetching raid data: {e}")

        return []

    async def _get_channel_update_data(self) -> list[dict]:
        """Get all channel update events (game/category changes)."""
        if not self.session:
            return []

        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.update"}
            logger.info(f"RAG Handler fetching channel update data from firehose API: {url} with params: {params}")

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    events = data.get("data", {}).get("events", [])
                    logger.info(f"RAG Handler channel updates: Got {len(events)} events from firehose API")
                    return events

        except Exception as e:
            logger.error(f"Error fetching channel update data: {e}")

        return []

    async def _get_game_context_for_timestamp(self, target_timestamp_str: str) -> dict | None:
        """Find the most recent channel.update before the given timestamp."""
        if not hasattr(self, "_cached_channel_updates") or not self._cached_channel_updates:
            raw_events = await self._get_channel_update_data()  # This fetches from the API
            parsed_events = []
            for event in raw_events:
                try:
                    # Parse timestamp to datetime object once for caching
                    event_time = datetime.fromisoformat(event["timestamp"])
                    parsed_events.append((event_time, event))
                except ValueError:
                    # Log cases where timestamp might be malformed or missing
                    logger.warning(f"Could not parse timestamp for event: {event.get('timestamp')}")
                    continue
            # Sort by datetime object descending for easy linear lookup
            self._cached_channel_updates = sorted(parsed_events, key=lambda x: x[0], reverse=True)

        try:
            # Parse target timestamp to datetime object once
            target_dt = datetime.fromisoformat(target_timestamp_str)
        except ValueError:
            # Handle invalid target_timestamp format
            logger.warning(f"Invalid target_timestamp format: {target_timestamp_str}")
            return None

        # Find most recent update before target_timestamp
        for event_dt, event_data in self._cached_channel_updates:
            if event_dt <= target_dt:
                return event_data.get("data", {})

        return None

    async def _build_game_context(self, retrieved_data: dict[str, Any]) -> str | None:
        """Build game/category context from chat messages and channel updates."""
        chat_messages = retrieved_data.get("raw_data", {}).get("chat_messages", [])
        if not chat_messages:
            return None

        # Get unique game contexts for all chat messages
        game_contexts = set()
        for message in chat_messages:
            # Extract timestamp from message data
            timestamp = message.get("timestamp") or message.get("data", {}).get("timestamp")
            if timestamp:
                game_data = await self._get_game_context_for_timestamp(timestamp)
                if game_data:
                    category_name = game_data.get("category_name")
                    title = game_data.get("title")
                    if category_name:
                        context_entry = f"Game: {category_name}"
                        if title:
                            context_entry += f" (Stream Title: '{title}')"
                        game_contexts.add(context_entry)

        if game_contexts:
            contexts_text = "\n- ".join(sorted(game_contexts))
            return f"\nStream Game Context:\n- {contexts_text}"

        return None

    def _build_session_context(self, sessions: list[dict]) -> str:
        """Build context describing stream sessions."""
        if not sessions:
            return ""

        context_parts = []

        for session in sessions:
            status = session.get("status", "unknown")
            start_time = session.get("start_time")
            end_time = session.get("end_time")
            message_count = session.get("message_count", 0)
            unique_chatters = session.get("unique_chatters", 0)
            game_changes = session.get("game_changes", 0)

            if status == "live":
                session_desc = "📺 Current Stream Session (LIVE)"
                if start_time:
                    session_desc += f"\n  Started: {start_time}"
                session_desc += "\n  Status: Currently streaming"
            else:
                session_desc = "📺 Previous Stream Session"
                if start_time and end_time:
                    session_desc += f"\n  Duration: {start_time} to {end_time}"
                elif start_time:
                    session_desc += f"\n  Started: {start_time}"
                session_desc += "\n  Status: Completed"

            session_desc += f"\n  Chat Activity: {message_count} messages from {unique_chatters} unique viewers"

            if game_changes > 0:
                session_desc += f"\n  Game Changes: {game_changes} category/title updates during session"

            context_parts.append(session_desc)

        if len(sessions) == 1:
            header = "Stream Session Context:"
        else:
            header = f"Stream Sessions Context ({len(sessions)} sessions):"

        return f"\n{header}\n" + "\n\n".join(context_parts)

    async def _get_cheer_data(self) -> list[dict]:
        """Get all cheer/bits events."""
        if not self.session:
            return []

        try:
            url = f"{self.server_url}/api/activity/events"
            params = {"event_type": "channel.cheer"}
            logger.info(f"RAG Handler fetching cheer data from firehose API: {url} with params: {params}")

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    events = data.get("data", {}).get("events", [])
                    logger.info(f"RAG Handler cheer: Got {len(events)} events from firehose API")
                    return events

        except Exception as e:
            logger.error(f"Error fetching cheer data: {e}")

        return []

    async def _get_activity_stats(self) -> dict:
        """Get activity statistics."""
        if not self.session:
            return {}

        try:
            url = f"{self.server_url}/api/activity/stats"
            params = {}

            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    return data.get("data", {}).get("stats", {})

        except Exception as e:
            logger.error(f"Error fetching activity stats: {e}")

        return {}

    async def _get_context_patterns(self, hours: int | None) -> dict:
        """
        Get AI-analyzed context patterns.

        Note: This is the ONLY data retrieval method that respects time filtering.
        All other data sources (_get_subscription_data, _get_follower_data, etc.)
        are unbounded and return all available data regardless of time windows.
        """
        if hours is not None:
            stats = await self.context_client.get_context_stats(hours)
        else:
            # Get all-time stats when no time limit specified
            stats = await self.context_client.get_context_stats(8760)  # 1 year
        contexts = await self.context_client.get_contexts(limit=10)

        return {"stats": stats, "recent_contexts": contexts}

    async def _search_contexts(self, search_term: str) -> list[dict]:
        """Search context transcripts."""
        return await self.context_client.search_contexts(search_term, limit=10)

    def _extract_search_terms(self, question: str) -> str:
        """Extract potential search terms from question."""
        # Remove common question words
        stop_words = {
            "what",
            "when",
            "where",
            "who",
            "why",
            "how",
            "did",
            "do",
            "does",
            "is",
            "are",
            "was",
            "were",
            "the",
            "a",
            "an",
            "i",
            "me",
            "my",
            "last",
            "recent",
            "recently",
            "today",
            "yesterday",
        }

        words = question.lower().split()
        keywords = [w for w in words if w not in stop_words and len(w) > 2]

        return " ".join(keywords[:3])  # Use top 3 keywords

    def _format_subscription_data(self, subs: list[dict]) -> str:
        """Format subscription data for context."""
        if not subs:
            return "No subscriptions found"

        lines = []
        tier_counts = {}
        total_months = 0

        for sub in subs[:10]:  # Limit to recent 10
            data = sub.get("data", {})
            tier = data.get("tier", "1000")
            months = data.get("cumulative_months", 1)

            tier_counts[tier] = tier_counts.get(tier, 0) + 1
            total_months += months

            lines.append(f"- {sub.get('user_name', 'Unknown')}: Tier {tier[0]} ({months} months)")

        summary = f"Total: {len(subs)} subs"
        if tier_counts:
            summary += f", Tiers: {tier_counts}"
        if total_months > len(subs):
            summary += f", Avg tenure: {total_months / len(subs):.1f} months"

        return summary + "\n" + "\n".join(lines[:5])

    def _format_follower_data(self, followers: list[dict]) -> str:
        """Format follower data for context."""
        if not followers:
            return "No new followers found"

        lines = [f"Total new followers: {len(followers)}"]
        for follower in followers[:5]:
            lines.append(f"- {follower.get('user_name', 'Unknown')}")

        return "\n".join(lines)

    def _format_chat_data(self, messages: list[dict]) -> str:
        """Format chat data for context."""
        if not messages:
            return "No chat messages found"

        lines = [f"Total messages: {len(messages)}"]

        # Get unique chatters and collect emotes
        chatters = set()
        all_emotes = set()

        for msg in messages:
            # Handle case where msg might be a string instead of dict
            if isinstance(msg, dict):
                if user := msg.get("user_name"):
                    chatters.add(user)

                # Extract emotes from this message
                data = msg.get("data", {})
                if isinstance(data, dict):
                    message = data.get("message", "")
                    text = message.get("text", "") if isinstance(message, dict) else str(message) if message else ""
                    if text:
                        emotes = self._extract_emotes_from_text(text)
                        all_emotes.update(emotes)
            else:
                logger.warning(f"Expected dict for chat message, got {type(msg)}: {msg}")

        lines.append(f"Active chatters: {len(chatters)}")

        # Add emotes section
        if all_emotes:
            lines.append(f"Channel emotes used: {', '.join(sorted(all_emotes))}")

        # Show ALL chat messages for full context
        lines.append(f"\nALL chat messages ({len(messages)} total):")
        message_count = 0
        for msg in messages:  # ALL messages, no sampling
            # Handle case where msg might be a string instead of dict
            if not isinstance(msg, dict):
                logger.warning(f"Skipping non-dict message: {type(msg)} - {msg}")
                continue

            data = msg.get("data", {})
            # Handle case where data might be a string instead of dict
            if isinstance(data, dict):
                # Message can be either a string directly or nested in a text field
                message = data.get("message", "")
                text = message.get("text", "") if isinstance(message, dict) else str(message) if message else ""
            else:
                text = str(data) if data else ""

            if text:
                # Show full message text, not truncated
                username = msg.get("user_name", "Unknown")
                lines.append(f"- {username}: {text}")
                message_count += 1

        if message_count == 0:
            lines.append("- No recent messages with text content")

        return "\n".join(lines)

    def _format_stream_info(self, info: dict) -> str:
        """Format stream info for context."""
        if not info:
            return "Stream information not available"

        stream = info.get("stream", {})
        channel = info.get("channel", {})

        lines = []
        if stream.get("type") == "live":
            lines.append("Stream is LIVE")
            lines.append(f"Title: {stream.get('title', 'Unknown')}")
            lines.append(f"Game: {stream.get('game_name', 'Unknown')}")
            lines.append(f"Viewers: {stream.get('viewer_count', 0)}")
            lines.append(f"Started: {stream.get('started_at', 'Unknown')}")
        else:
            lines.append("Stream is OFFLINE")

        if channel:
            lines.append(f"Broadcaster: {channel.get('broadcaster_name', 'Unknown')}")

        return "\n".join(lines)

    def _format_context_analysis(self, data: dict) -> str:
        """Format AI context analysis for context."""
        lines = []

        if stats := data.get("stats"):
            lines.append(f"Context windows analyzed: {stats.get('total_contexts', 0)}")
            if stats.get("average_sentiment"):
                lines.append(f"Average sentiment: {stats['average_sentiment']}")

        if contexts := data.get("recent_contexts"):
            lines.append("\nRecent patterns detected:")
            for ctx in contexts[:3]:
                if patterns := ctx.get("patterns"):
                    lines.append(f"- Energy: {patterns.get('energy_level', 0):.1f}")
                    lines.append(f"  Topics: {', '.join(patterns.get('content_focus', []))}")
                    lines.append(f"  Sentiment: {ctx.get('sentiment', 'neutral')}")

        return "\n".join(lines) if lines else "No context analysis available"

    def _format_context_search(self, contexts: list[dict]) -> str:
        """Format context search results."""
        if not contexts:
            return "No matching contexts found"

        lines = [f"Found {len(contexts)} matching transcript segments:"]

        for ctx in contexts[:3]:
            transcript = ctx.get("transcript", "")[:200]
            lines.append(f"\n- {transcript}...")
            if sentiment := ctx.get("sentiment"):
                lines.append(f"  Sentiment: {sentiment}")

        return "\n".join(lines)


async def create_rag_endpoints(app: web.Application, rag_handler: RAGHandler):
    """
    Add RAG query endpoints to the health check web app.

    Endpoints:
    - POST /query - Process a natural language query
    - GET /query/examples - Get example queries
    """

    async def handle_query(request: web.Request):
        """Handle RAG query requests."""
        try:
            data = await request.json()
            question = data.get("question", "").strip()

            if not question:
                return web.json_response({"success": False, "error": "Question is required"}, status=400)

            # Optional time window parameter (only affects AI context pattern retrieval)
            time_window = data.get("time_window_hours")

            # Process the query
            result = await rag_handler.query(question, time_window)

            return web.json_response(result)

        except json.JSONDecodeError:
            return web.json_response({"success": False, "error": "Invalid JSON in request body"}, status=400)
        except Exception as e:
            logger.error(f"Error handling query: {e}")
            return web.json_response({"success": False, "error": str(e)}, status=500)

    async def get_examples(_request: web.Request):
        """Return example queries."""
        examples = {
            "subscription_queries": [
                "How many subs do I have today?",
                "Who subscribed in the last hour?",
                "How many tier 3 subs this stream?",
                "What's my average sub tenure?",
            ],
            "follower_queries": [
                "How many new followers today?",
                "Who followed in the last 2 hours?",
                "What's my follower count this stream?",
            ],
            "chat_queries": [
                "What happened in my chat?",
                "Who's been most active in my chat?",
                "What was the last thing someone said about the game?",
                "How active has my chat been?",
            ],
            "stream_queries": [
                "What game am I playing?",
                "How long have I been streaming?",
                "What's my stream title?",
                "How many viewers do I have?",
            ],
            "pattern_queries": [
                "What's the mood of my stream?",
                "How's the energy level in my chat?",
                "What topics have come up today?",
                "What's the sentiment been like?",
            ],
            "specific_queries": [
                "When did user123 last chat in my stream?",
                "Did anyone raid me today?",
                "How many bits were cheered in my stream?",
                "What happened in my stream in the last hour?",
            ],
        }

        return web.json_response({"examples": examples})

    # Add routes
    app.router.add_post("/query", handle_query)
    app.router.add_get("/query/examples", get_examples)

    logger.info("RAG query endpoints added at /query and /query/examples")
