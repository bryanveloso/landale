"""Training data preparation pipeline for AI model training."""

import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from context_client import ContextClient

logger = logging.getLogger(__name__)


class TrainingDataPipeline:
    """Pipeline for preparing training data from stored contexts."""

    def __init__(self, context_client: ContextClient, output_dir: str = "training_data"):
        self.context_client = context_client
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)

    async def prepare_conversation_dataset(
        self,
        session_filter: str | None = None,
        days_back: int = 30,
        min_context_length: int = 10,  # Minimum words in transcript
    ) -> str:
        """
        Prepare conversation training dataset from stored contexts.

        Args:
            session_filter: Optional session ID filter (e.g., "stream_2024_01_15")
            days_back: How many days back to collect data
            min_context_length: Minimum word count for transcript inclusion

        Returns:
            Path to generated dataset file
        """
        logger.info(f"Preparing conversation dataset (last {days_back} days)")

        # Get contexts from the last N days
        contexts = await self._fetch_contexts_by_timeframe(days_back, session_filter)

        if not contexts:
            logger.warning("No contexts found for dataset preparation")
            return ""

        # Filter contexts by minimum length
        filtered_contexts = [ctx for ctx in contexts if len(ctx.get("transcript", "").split()) >= min_context_length]

        logger.info(f"Filtered {len(filtered_contexts)} contexts from {len(contexts)} total")

        # Convert to training format
        training_data = []
        for ctx in filtered_contexts:
            training_entry = self._format_conversation_entry(ctx)
            if training_entry:
                training_data.append(training_entry)

        # Save dataset
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"conversation_dataset_{timestamp}.jsonl"
        filepath = self.output_dir / filename

        with open(filepath, "w", encoding="utf-8") as f:
            for entry in training_data:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        logger.info(f"Created conversation dataset: {filepath} ({len(training_data)} entries)")
        return str(filepath)

    async def prepare_pattern_dataset(
        self, session_filter: str | None = None, days_back: int = 30, include_dynamics: bool = True
    ) -> str:
        """
        Prepare pattern recognition training dataset.

        Args:
            session_filter: Optional session ID filter
            days_back: How many days back to collect data
            include_dynamics: Whether to include dynamics data

        Returns:
            Path to generated dataset file
        """
        logger.info(f"Preparing pattern dataset (last {days_back} days)")

        contexts = await self._fetch_contexts_by_timeframe(days_back, session_filter)

        if not contexts:
            logger.warning("No contexts found for pattern dataset")
            return ""

        # Filter contexts that have pattern data
        pattern_contexts = [ctx for ctx in contexts if ctx.get("patterns") or ctx.get("sentiment")]

        logger.info(f"Found {len(pattern_contexts)} contexts with pattern data")

        # Convert to training format
        training_data = []
        for ctx in pattern_contexts:
            pattern_entry = self._format_pattern_entry(ctx, include_dynamics)
            if pattern_entry:
                training_data.append(pattern_entry)

        # Save dataset
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"pattern_dataset_{timestamp}.jsonl"
        filepath = self.output_dir / filename

        with open(filepath, "w", encoding="utf-8") as f:
            for entry in training_data:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        logger.info(f"Created pattern dataset: {filepath} ({len(training_data)} entries)")
        return str(filepath)

    async def prepare_multimodal_dataset(
        self,
        session_filter: str | None = None,
        days_back: int = 30,
        include_chat: bool = True,
        include_interactions: bool = True,
    ) -> str:
        """
        Prepare multimodal training dataset with all available context.

        Args:
            session_filter: Optional session ID filter
            days_back: How many days back to collect data
            include_chat: Whether to include chat data
            include_interactions: Whether to include viewer interactions

        Returns:
            Path to generated dataset file
        """
        logger.info(f"Preparing multimodal dataset (last {days_back} days)")

        contexts = await self._fetch_contexts_by_timeframe(days_back, session_filter)

        if not contexts:
            logger.warning("No contexts found for multimodal dataset")
            return ""

        # Convert to comprehensive training format
        training_data = []
        for ctx in contexts:
            multimodal_entry = self._format_multimodal_entry(ctx, include_chat, include_interactions)
            if multimodal_entry:
                training_data.append(multimodal_entry)

        # Save dataset
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"multimodal_dataset_{timestamp}.jsonl"
        filepath = self.output_dir / filename

        with open(filepath, "w", encoding="utf-8") as f:
            for entry in training_data:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        logger.info(f"Created multimodal dataset: {filepath} ({len(training_data)} entries)")
        return str(filepath)

    async def prepare_temporal_dataset(
        self,
        session_filter: str | None = None,
        days_back: int = 30,
        context_window: int = 5,  # Number of consecutive contexts to group
    ) -> str:
        """
        Prepare temporal sequence dataset for understanding context flow.

        Args:
            session_filter: Optional session ID filter
            days_back: How many days back to collect data
            context_window: Number of consecutive contexts in each sequence

        Returns:
            Path to generated dataset file
        """
        logger.info(f"Preparing temporal dataset (last {days_back} days, window={context_window})")

        contexts = await self._fetch_contexts_by_timeframe(days_back, session_filter)

        if not contexts:
            logger.warning("No contexts found for temporal dataset")
            return ""

        # Group contexts by session and sort by time
        session_contexts = {}
        for ctx in contexts:
            session = ctx.get("session", "unknown")
            if session not in session_contexts:
                session_contexts[session] = []
            session_contexts[session].append(ctx)

        # Sort each session's contexts by start time
        for session in session_contexts:
            session_contexts[session].sort(key=lambda x: x.get("started", ""))

        # Create temporal sequences
        training_data = []
        for session, session_ctxs in session_contexts.items():
            if len(session_ctxs) < context_window:
                continue

            # Create sliding windows
            for i in range(len(session_ctxs) - context_window + 1):
                sequence = session_ctxs[i : i + context_window]
                temporal_entry = self._format_temporal_entry(sequence, session)
                if temporal_entry:
                    training_data.append(temporal_entry)

        # Save dataset
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"temporal_dataset_{timestamp}.jsonl"
        filepath = self.output_dir / filename

        with open(filepath, "w", encoding="utf-8") as f:
            for entry in training_data:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        logger.info(f"Created temporal dataset: {filepath} ({len(training_data)} entries)")
        return str(filepath)

    async def _fetch_contexts_by_timeframe(
        self, days_back: int, session_filter: str | None = None
    ) -> list[dict[str, Any]]:
        """Fetch contexts from the specified timeframe."""
        # For now, fetch all contexts and filter by time
        # In the future, the context client could support time-based queries
        all_contexts = await self.context_client.get_contexts(limit=1000, session=session_filter)

        if not all_contexts:
            return []

        # Filter by timeframe
        cutoff_time = datetime.now() - timedelta(days=days_back)

        filtered_contexts = []
        for ctx in all_contexts:
            try:
                started_str = ctx.get("started", "")
                if started_str:
                    started_time = datetime.fromisoformat(started_str.replace("Z", "+00:00"))
                    if started_time.replace(tzinfo=None) >= cutoff_time:
                        filtered_contexts.append(ctx)
            except (ValueError, TypeError):
                # Skip contexts with invalid timestamps
                continue

        return filtered_contexts

    def _format_conversation_entry(self, context: dict[str, Any]) -> dict[str, Any] | None:
        """Format a context for conversation training."""
        transcript = context.get("transcript", "").strip()
        if not transcript:
            return None

        # Basic conversation format
        entry = {
            "input": transcript,
            "context": {
                "session": context.get("session", ""),
                "timestamp": context.get("started", ""),
                "duration": context.get("duration", 0),
            },
        }

        # Add chat context if available
        chat_data = context.get("chat", {})
        if chat_data and isinstance(chat_data, dict):
            entry["context"]["chat_activity"] = {
                "message_count": chat_data.get("message_count", 0),
                "participants": chat_data.get("participants", []),
                "velocity": chat_data.get("velocity", 0),
            }

        # Add sentiment if available
        if context.get("sentiment"):
            entry["context"]["sentiment"] = context["sentiment"]

        return entry

    def _format_pattern_entry(self, context: dict[str, Any], include_dynamics: bool = True) -> dict[str, Any] | None:
        """Format a context for pattern recognition training."""
        transcript = context.get("transcript", "").strip()
        if not transcript:
            return None

        patterns = context.get("patterns", {})
        if not patterns:
            return None

        entry = {
            "input": transcript,
            "patterns": patterns,
            "metadata": {
                "session": context.get("session", ""),
                "timestamp": context.get("started", ""),
                "duration": context.get("duration", 0),
            },
        }

        # Add sentiment
        if context.get("sentiment"):
            entry["sentiment"] = context["sentiment"]

        # Add dynamics if requested and available
        if include_dynamics and context.get("dynamics"):
            entry["dynamics"] = context["dynamics"]

        # Add topics if available
        if context.get("topics"):
            entry["topics"] = context["topics"]

        return entry

    def _format_multimodal_entry(
        self, context: dict[str, Any], include_chat: bool, include_interactions: bool
    ) -> dict[str, Any] | None:
        """Format a context for multimodal training."""
        transcript = context.get("transcript", "").strip()
        if not transcript:
            return None

        entry = {
            "transcript": transcript,
            "metadata": {
                "session": context.get("session", ""),
                "timestamp": context.get("started", ""),
                "duration": context.get("duration", 0),
            },
        }

        # Add chat data
        if include_chat and context.get("chat"):
            entry["chat"] = context["chat"]

        # Add viewer interactions
        if include_interactions and context.get("interactions"):
            entry["interactions"] = context["interactions"]

        # Add emote data
        if context.get("emotes"):
            entry["emotes"] = context["emotes"]

        # Add AI analysis if available
        if context.get("patterns"):
            entry["patterns"] = context["patterns"]

        if context.get("sentiment"):
            entry["sentiment"] = context["sentiment"]

        if context.get("topics"):
            entry["topics"] = context["topics"]

        return entry

    def _format_temporal_entry(self, sequence: list[dict[str, Any]], session: str) -> dict[str, Any] | None:
        """Format a sequence of contexts for temporal training."""
        if not sequence:
            return None

        # Create temporal sequence
        contexts = []
        for ctx in sequence:
            context_summary = {
                "timestamp": ctx.get("started", ""),
                "duration": ctx.get("duration", 0),
                "transcript": ctx.get("transcript", ""),
                "sentiment": ctx.get("sentiment", "neutral"),
            }

            # Add pattern data if available
            if ctx.get("patterns"):
                context_summary["patterns"] = ctx["patterns"]

            contexts.append(context_summary)

        entry = {
            "session": session,
            "sequence": contexts,
            "metadata": {
                "sequence_length": len(contexts),
                "total_duration": sum(ctx.get("duration", 0) for ctx in sequence),
                "start_time": sequence[0].get("started", ""),
                "end_time": sequence[-1].get("started", ""),
            },
        }

        return entry

    async def get_dataset_stats(self) -> dict[str, Any]:
        """Get statistics about available training data."""
        logger.info("Gathering dataset statistics")

        # Get all contexts
        all_contexts = await self.context_client.get_contexts(limit=10000)

        if not all_contexts:
            return {"total_contexts": 0}

        # Analyze contexts
        stats = {
            "total_contexts": len(all_contexts),
            "sessions": set(),
            "date_range": {"earliest": None, "latest": None},
            "content_stats": {
                "total_words": 0,
                "total_duration": 0,
                "with_patterns": 0,
                "with_chat": 0,
                "with_interactions": 0,
            },
        }

        for ctx in all_contexts:
            # Session tracking
            if ctx.get("session"):
                stats["sessions"].add(ctx["session"])

            # Date range
            if ctx.get("started"):
                try:
                    started = datetime.fromisoformat(ctx["started"].replace("Z", "+00:00"))
                    if not stats["date_range"]["earliest"] or started < stats["date_range"]["earliest"]:
                        stats["date_range"]["earliest"] = started
                    if not stats["date_range"]["latest"] or started > stats["date_range"]["latest"]:
                        stats["date_range"]["latest"] = started
                except (ValueError, TypeError):
                    pass

            # Content analysis
            transcript = ctx.get("transcript", "")
            if transcript:
                stats["content_stats"]["total_words"] += len(transcript.split())

            if ctx.get("duration"):
                stats["content_stats"]["total_duration"] += ctx["duration"]

            if ctx.get("patterns"):
                stats["content_stats"]["with_patterns"] += 1

            if ctx.get("chat"):
                stats["content_stats"]["with_chat"] += 1

            if ctx.get("interactions"):
                stats["content_stats"]["with_interactions"] += 1

        # Convert date range to strings
        if stats["date_range"]["earliest"]:
            stats["date_range"]["earliest"] = stats["date_range"]["earliest"].isoformat()
        if stats["date_range"]["latest"]:
            stats["date_range"]["latest"] = stats["date_range"]["latest"].isoformat()

        stats["unique_sessions"] = len(stats["sessions"])
        stats["sessions"] = list(stats["sessions"])

        return stats
