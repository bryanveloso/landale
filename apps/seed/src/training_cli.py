"""Command-line interface for training data preparation."""
import asyncio
import argparse
import logging
import sys
from pathlib import Path

from .context_client import ContextClient
from .training_pipeline import TrainingDataPipeline
from .dataset_exporter import DatasetExporter

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


async def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        description="SEED Training Data Pipeline CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate conversation dataset for last 7 days
  python -m seed.training_cli prepare --type conversation --days 7
  
  # Export Hugging Face format with train/val split
  python -m seed.training_cli export --format huggingface --type multimodal
  
  # Get training data statistics
  python -m seed.training_cli stats
  
  # Export OpenAI fine-tuning format
  python -m seed.training_cli export --format openai --session stream_2024_01_15
        """
    )
    
    parser.add_argument(
        '--server-url',
        default='http://localhost:8080',
        help='Phoenix server URL (default: http://localhost:8080)'
    )
    
    parser.add_argument(
        '--output-dir',
        default='./training_data',
        help='Output directory for generated files (default: ./training_data)'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Prepare command
    prepare_parser = subparsers.add_parser('prepare', help='Prepare training datasets')
    prepare_parser.add_argument(
        '--type',
        choices=['conversation', 'pattern', 'multimodal', 'temporal'],
        default='conversation',
        help='Type of dataset to prepare (default: conversation)'
    )
    prepare_parser.add_argument(
        '--days',
        type=int,
        default=30,
        help='Number of days back to collect data (default: 30)'
    )
    prepare_parser.add_argument(
        '--session',
        help='Filter by specific session ID (e.g., stream_2024_01_15)'
    )
    prepare_parser.add_argument(
        '--min-length',
        type=int,
        default=10,
        help='Minimum word count for transcript inclusion (default: 10)'
    )
    
    # Export command
    export_parser = subparsers.add_parser('export', help='Export datasets in specific formats')
    export_parser.add_argument(
        '--format',
        choices=['huggingface', 'openai', 'csv'],
        required=True,
        help='Export format'
    )
    export_parser.add_argument(
        '--type',
        choices=['conversation', 'pattern', 'multimodal', 'temporal'],
        default='conversation',
        help='Type of dataset to export (default: conversation)'
    )
    export_parser.add_argument(
        '--days',
        type=int,
        default=30,
        help='Number of days back to collect data (default: 30)'
    )
    export_parser.add_argument(
        '--session',
        help='Filter by specific session ID'
    )
    export_parser.add_argument(
        '--max-examples',
        type=int,
        default=1000,
        help='Maximum number of examples for OpenAI format (default: 1000)'
    )
    export_parser.add_argument(
        '--train-split',
        type=float,
        default=0.8,
        help='Training split ratio for Hugging Face format (default: 0.8)'
    )
    
    # Stats command
    stats_parser = subparsers.add_parser('stats', help='Show training data statistics')
    
    # Summary command
    summary_parser = subparsers.add_parser('summary', help='Generate training data summary')
    summary_parser.add_argument(
        '--days',
        type=int,
        default=30,
        help='Number of days back to analyze (default: 30)'
    )
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
        
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Initialize clients
    logger.info(f"Connecting to server: {args.server_url}")
    async with ContextClient(args.server_url) as context_client:
        pipeline = TrainingDataPipeline(context_client, str(output_dir))
        exporter = DatasetExporter(context_client, str(output_dir))
        
        try:
            if args.command == 'prepare':
                await handle_prepare_command(args, pipeline)
            elif args.command == 'export':
                await handle_export_command(args, exporter)
            elif args.command == 'stats':
                await handle_stats_command(args, pipeline)
            elif args.command == 'summary':
                await handle_summary_command(args, exporter)
        except Exception as e:
            logger.error(f"Command failed: {e}")
            sys.exit(1)


async def handle_prepare_command(args, pipeline: TrainingDataPipeline):
    """Handle the prepare command."""
    logger.info(f"Preparing {args.type} dataset (last {args.days} days)")
    
    if args.type == 'conversation':
        filepath = await pipeline.prepare_conversation_dataset(
            session_filter=args.session,
            days_back=args.days,
            min_context_length=args.min_length
        )
    elif args.type == 'pattern':
        filepath = await pipeline.prepare_pattern_dataset(
            session_filter=args.session,
            days_back=args.days
        )
    elif args.type == 'multimodal':
        filepath = await pipeline.prepare_multimodal_dataset(
            session_filter=args.session,
            days_back=args.days
        )
    elif args.type == 'temporal':
        filepath = await pipeline.prepare_temporal_dataset(
            session_filter=args.session,
            days_back=args.days
        )
    else:
        raise ValueError(f"Unknown dataset type: {args.type}")
        
    if filepath:
        print(f"✅ Dataset prepared: {filepath}")
    else:
        print("❌ No data found for dataset preparation")


async def handle_export_command(args, exporter: DatasetExporter):
    """Handle the export command."""
    logger.info(f"Exporting {args.type} dataset in {args.format} format")
    
    if args.format == 'huggingface':
        val_split = 1.0 - args.train_split
        split_ratio = {"train": args.train_split, "validation": val_split}
        
        files = await exporter.export_huggingface_dataset(
            dataset_type=args.type,
            session_filter=args.session,
            days_back=args.days,
            split_ratio=split_ratio
        )
        
        if files:
            print("✅ Hugging Face dataset exported:")
            for split, filepath in files.items():
                print(f"  {split}: {filepath}")
        else:
            print("❌ No data found for export")
            
    elif args.format == 'openai':
        filepath = await exporter.export_openai_format(
            session_filter=args.session,
            days_back=args.days,
            max_examples=args.max_examples
        )
        
        if filepath:
            print(f"✅ OpenAI dataset exported: {filepath}")
        else:
            print("❌ No data found for export")
            
    elif args.format == 'csv':
        filepath = await exporter.export_csv_format(
            dataset_type=args.type,
            session_filter=args.session,
            days_back=args.days
        )
        
        if filepath:
            print(f"✅ CSV dataset exported: {filepath}")
        else:
            print("❌ No data found for export")


async def handle_stats_command(args, pipeline: TrainingDataPipeline):
    """Handle the stats command."""
    logger.info("Gathering dataset statistics")
    
    stats = await pipeline.get_dataset_stats()
    
    print("\n📊 Training Data Statistics")
    print("=" * 50)
    print(f"Total contexts: {stats['total_contexts']}")
    print(f"Unique sessions: {stats['unique_sessions']}")
    
    if stats['date_range']['earliest'] and stats['date_range']['latest']:
        print(f"Date range: {stats['date_range']['earliest']} to {stats['date_range']['latest']}")
        
    content_stats = stats['content_stats']
    print(f"\nContent Statistics:")
    print(f"  Total words: {content_stats['total_words']:,}")
    print(f"  Total duration: {content_stats['total_duration']:.1f} seconds")
    print(f"  Contexts with patterns: {content_stats['with_patterns']}")
    print(f"  Contexts with chat: {content_stats['with_chat']}")
    print(f"  Contexts with interactions: {content_stats['with_interactions']}")
    
    # Show recent sessions
    if stats['sessions']:
        print(f"\nRecent sessions:")
        for session in sorted(stats['sessions'])[-10:]:  # Last 10 sessions
            print(f"  {session}")


async def handle_summary_command(args, exporter: DatasetExporter):
    """Handle the summary command."""
    logger.info("Generating training data summary")
    
    filepath = await exporter.export_training_summary(days_back=args.days)
    
    if filepath:
        print(f"✅ Training summary generated: {filepath}")
        
        # Show brief summary in console
        import json
        with open(filepath, 'r') as f:
            summary = json.load(f)
            
        stats = summary['dataset_statistics']
        recommendations = summary['training_recommendations']
        
        print(f"\n📋 Summary (last {args.days} days)")
        print("=" * 40)
        print(f"Data quality: {recommendations['data_quality']}")
        print(f"Total contexts: {stats['total_contexts']}")
        print(f"Recommended models: {', '.join(recommendations['recommended_models'])}")
        
        if recommendations['potential_issues']:
            print(f"⚠️  Issues: {', '.join(recommendations['potential_issues'])}")
    else:
        print("❌ Failed to generate summary")


if __name__ == '__main__':
    asyncio.run(main())