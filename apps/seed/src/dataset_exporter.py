"""Dataset export utilities for AI training."""

import csv
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any

from .context_client import ContextClient
from .training_pipeline import TrainingDataPipeline

logger = logging.getLogger(__name__)


class DatasetExporter:
    """Export training datasets in various formats for different AI frameworks."""

    def __init__(self, context_client: ContextClient, output_dir: str = "exports"):
        self.context_client = context_client
        self.pipeline = TrainingDataPipeline(context_client, output_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)

    async def export_huggingface_dataset(
        self,
        dataset_type: str = "conversation",
        session_filter: str | None = None,
        days_back: int = 30,
        split_ratio: dict[str, float] | None = None,
    ) -> dict[str, str]:
        """
        Export dataset in Hugging Face format.

        Args:
            dataset_type: Type of dataset ("conversation", "pattern", "multimodal", "temporal")
            session_filter: Optional session ID filter
            days_back: How many days back to collect data
            split_ratio: Train/validation split ratios

        Returns:
            Dictionary with paths to train/validation files
        """
        if split_ratio is None:
            split_ratio = {"train": 0.8, "validation": 0.2}

        logger.info(f"Exporting Hugging Face {dataset_type} dataset")

        # Generate base dataset
        if dataset_type == "conversation":
            base_file = await self.pipeline.prepare_conversation_dataset(session_filter, days_back)
        elif dataset_type == "pattern":
            base_file = await self.pipeline.prepare_pattern_dataset(session_filter, days_back)
        elif dataset_type == "multimodal":
            base_file = await self.pipeline.prepare_multimodal_dataset(session_filter, days_back)
        elif dataset_type == "temporal":
            base_file = await self.pipeline.prepare_temporal_dataset(session_filter, days_back)
        else:
            raise ValueError(f"Unknown dataset type: {dataset_type}")

        if not base_file:
            return {}

        # Load and split data
        data = []
        with open(base_file, encoding="utf-8") as f:
            for line in f:
                data.append(json.loads(line))

        # Split data
        train_size = int(len(data) * split_ratio["train"])
        train_data = data[:train_size]
        val_data = data[train_size:]

        # Create split files
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base_name = f"hf_{dataset_type}_{timestamp}"

        train_file = self.output_dir / f"{base_name}_train.jsonl"
        val_file = self.output_dir / f"{base_name}_val.jsonl"

        # Write training set
        with open(train_file, "w", encoding="utf-8") as f:
            for entry in train_data:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        # Write validation set
        with open(val_file, "w", encoding="utf-8") as f:
            for entry in val_data:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        # Create dataset config
        config_file = self.output_dir / f"{base_name}_config.json"
        config = {
            "dataset_info": {
                "description": f"SEED {dataset_type} dataset for AI training",
                "features": self._get_features_schema(dataset_type),
                "splits": {"train": {"num_examples": len(train_data)}, "validation": {"num_examples": len(val_data)}},
                "download_size": sum(Path(f).stat().st_size for f in [train_file, val_file]),
                "dataset_size": sum(Path(f).stat().st_size for f in [train_file, val_file]),
            },
            "builder_name": f"seed_{dataset_type}",
            "config_name": "default",
            "version": {"version_str": "1.0.0", "major": 1, "minor": 0, "patch": 0},
        }

        with open(config_file, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)

        logger.info(f"Created Hugging Face dataset: train={len(train_data)}, val={len(val_data)}")

        return {"train": str(train_file), "validation": str(val_file), "config": str(config_file)}

    async def export_openai_format(
        self, session_filter: str | None = None, days_back: int = 30, max_examples: int = 1000
    ) -> str:
        """
        Export dataset in OpenAI fine-tuning format.

        Args:
            session_filter: Optional session ID filter
            days_back: How many days back to collect data
            max_examples: Maximum number of examples to include

        Returns:
            Path to generated JSONL file
        """
        logger.info("Exporting OpenAI fine-tuning dataset")

        # Get conversation dataset
        base_file = await self.pipeline.prepare_conversation_dataset(session_filter, days_back)

        if not base_file:
            return ""

        # Load and convert to OpenAI format
        openai_data = []
        with open(base_file, encoding="utf-8") as f:
            for i, line in enumerate(f):
                if i >= max_examples:
                    break

                data = json.loads(line)

                # Convert to OpenAI chat format
                openai_entry = {
                    "messages": [
                        {
                            "role": "system",
                            "content": "You are an AI companion that understands streaming context and viewer interactions.",
                        },
                        {"role": "user", "content": f"Analyze this stream moment: {data['input']}"},
                        {"role": "assistant", "content": self._generate_assistant_response(data)},
                    ]
                }

                openai_data.append(openai_entry)

        # Save OpenAI format
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"openai_dataset_{timestamp}.jsonl"
        filepath = self.output_dir / filename

        with open(filepath, "w", encoding="utf-8") as f:
            for entry in openai_data:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        logger.info(f"Created OpenAI dataset: {filepath} ({len(openai_data)} examples)")
        return str(filepath)

    async def export_csv_format(
        self, dataset_type: str = "conversation", session_filter: str | None = None, days_back: int = 30
    ) -> str:
        """
        Export dataset in CSV format for analysis tools.

        Args:
            dataset_type: Type of dataset to export
            session_filter: Optional session ID filter
            days_back: How many days back to collect data

        Returns:
            Path to generated CSV file
        """
        logger.info(f"Exporting CSV {dataset_type} dataset")

        # Generate base dataset
        if dataset_type == "conversation":
            base_file = await self.pipeline.prepare_conversation_dataset(session_filter, days_back)
        elif dataset_type == "pattern":
            base_file = await self.pipeline.prepare_pattern_dataset(session_filter, days_back)
        else:
            base_file = await self.pipeline.prepare_multimodal_dataset(session_filter, days_back)

        if not base_file:
            return ""

        # Convert to CSV
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"csv_{dataset_type}_{timestamp}.csv"
        filepath = self.output_dir / filename

        with open(base_file, encoding="utf-8") as jsonl_file:
            data = [json.loads(line) for line in jsonl_file]

        if not data:
            return ""

        # Flatten data for CSV
        flattened_data = []
        for entry in data:
            flat_entry = self._flatten_dict(entry)
            flattened_data.append(flat_entry)

        # Get all possible columns
        all_columns = set()
        for entry in flattened_data:
            all_columns.update(entry.keys())

        # Write CSV
        with open(filepath, "w", newline="", encoding="utf-8") as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=sorted(all_columns))
            writer.writeheader()
            writer.writerows(flattened_data)

        logger.info(f"Created CSV dataset: {filepath} ({len(flattened_data)} rows)")
        return str(filepath)

    async def export_training_summary(self, days_back: int = 30) -> str:
        """
        Export a comprehensive training data summary.

        Args:
            days_back: How many days back to analyze

        Returns:
            Path to generated summary file
        """
        logger.info("Generating training data summary")

        # Get dataset statistics
        stats = await self.pipeline.get_dataset_stats()

        # Generate summary
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"training_summary_{timestamp}.json"
        filepath = self.output_dir / filename

        summary = {
            "generated_at": datetime.now().isoformat(),
            "analysis_period_days": days_back,
            "dataset_statistics": stats,
            "training_recommendations": self._generate_training_recommendations(stats),
            "export_metadata": {
                "available_formats": ["huggingface", "openai", "csv"],
                "recommended_splits": {"train": 0.8, "validation": 0.15, "test": 0.05},
            },
        }

        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2, ensure_ascii=False)

        logger.info(f"Created training summary: {filepath}")
        return str(filepath)

    def _get_features_schema(self, dataset_type: str) -> dict[str, dict[str, str]]:
        """Get Hugging Face features schema for dataset type."""
        schemas = {
            "conversation": {
                "input": {"dtype": "string", "_type": "Value"},
                "context": {"dtype": "string", "_type": "Value"},
            },
            "pattern": {
                "input": {"dtype": "string", "_type": "Value"},
                "patterns": {"dtype": "string", "_type": "Value"},
                "sentiment": {"dtype": "string", "_type": "Value"},
            },
            "multimodal": {
                "transcript": {"dtype": "string", "_type": "Value"},
                "chat": {"dtype": "string", "_type": "Value"},
                "patterns": {"dtype": "string", "_type": "Value"},
            },
        }
        return schemas.get(
            dataset_type,
            {"sequence": {"dtype": "string", "_type": "Value"}, "session": {"dtype": "string", "_type": "Value"}},
        )

    def _generate_assistant_response(self, data: dict[str, Any]) -> str:
        """Generate assistant response for OpenAI format."""
        response_parts = []

        # Add context analysis
        context = data.get("context", {})
        if context.get("sentiment"):
            response_parts.append(f"Sentiment: {context['sentiment']}")

        if context.get("chat_activity"):
            chat = context["chat_activity"]
            response_parts.append(
                f"Chat activity: {chat.get('message_count', 0)} messages from "
                f"{len(chat.get('participants', []))} participants"
            )

        # Add duration context
        if context.get("duration"):
            minutes = context["duration"] / 60
            response_parts.append(f"Duration: {minutes:.1f} minutes")

        if not response_parts:
            response_parts.append("Analyzing stream context and viewer engagement.")

        return " | ".join(response_parts)

    def _flatten_dict(self, d: dict[str, Any], parent_key: str = "", sep: str = "_") -> dict[str, Any]:
        """Flatten nested dictionary for CSV export."""
        items = []
        for k, v in d.items():
            new_key = f"{parent_key}{sep}{k}" if parent_key else k
            if isinstance(v, dict):
                items.extend(self._flatten_dict(v, new_key, sep=sep).items())
            elif isinstance(v, list):
                # Convert lists to comma-separated strings
                items.append((new_key, ",".join(str(item) for item in v)))
            else:
                items.append((new_key, v))
        return dict(items)

    def _generate_training_recommendations(self, stats: dict[str, Any]) -> dict[str, Any]:
        """Generate training recommendations based on dataset statistics."""
        recommendations = {
            "data_quality": "good",
            "recommended_models": [],
            "training_tips": [],
            "potential_issues": [],
        }

        content_stats = stats.get("content_stats", {})
        total_contexts = stats.get("total_contexts", 0)

        # Data quality assessment
        if total_contexts < 100:
            recommendations["data_quality"] = "limited"
            recommendations["potential_issues"].append("Small dataset size may limit model performance")
        elif total_contexts < 500:
            recommendations["data_quality"] = "moderate"

        # Model recommendations based on data characteristics
        with_patterns = content_stats.get("with_patterns", 0)
        with_chat = content_stats.get("with_chat", 0)

        if with_patterns > total_contexts * 0.5:
            recommendations["recommended_models"].append("Pattern classification model")

        if with_chat > total_contexts * 0.3:
            recommendations["recommended_models"].append("Multimodal conversation model")

        # Training tips
        if content_stats.get("total_words", 0) > 50000:
            recommendations["training_tips"].append("Sufficient text data for language model fine-tuning")

        if len(stats.get("sessions", [])) > 10:
            recommendations["training_tips"].append("Multiple sessions available for temporal modeling")

        return recommendations
