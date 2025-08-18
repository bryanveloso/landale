"""Integration module for importing and analyzing quotes through the text analysis pipeline.

This module orchestrates the import of quotes from Elsydeon API and processes them
through the text analysis pipeline to extract vocabulary and insights.
"""

import asyncio
from datetime import datetime

from .logger import get_logger
from .quotes_api import ElsydeonQuotesClient, QuotesDataProcessor, bulk_import_all_quotes, import_recent_quotes
from .text_analysis import TextAnalysisService, get_text_analysis_service
from .text_analysis_schema import TextAnalysisOutput

logger = get_logger(__name__)


class QuotesAnalysisIntegration:
    """Integrates quotes import with text analysis pipeline."""

    def __init__(self, text_analysis_service: TextAnalysisService | None = None):
        """Initialize the integration.

        Args:
            text_analysis_service: Optional service instance
        """
        self.text_analysis_service = text_analysis_service or get_text_analysis_service()
        self.processed_count = 0
        self.analysis_results: list[TextAnalysisOutput] = []

    async def import_and_analyze_recent_quotes(self, limit: int = 100, days: int = 30) -> dict:
        """Import recent quotes and analyze them for vocabulary.

        Args:
            limit: Maximum number of quotes to import
            days: Number of days back to search

        Returns:
            Analysis summary dictionary
        """
        logger.info("Starting recent quotes import and analysis", limit=limit, days=days)

        start_time = datetime.utcnow()

        try:
            # Import quotes
            quotes_inputs = await import_recent_quotes(limit=limit, days=days)

            if not quotes_inputs:
                logger.warning("No quotes imported for analysis")
                return self._create_summary(start_time, 0, [])

            # Analyze quotes through text analysis pipeline
            analysis_results = await self.text_analysis_service.batch_analyze(quotes_inputs)

            # Store results
            self.analysis_results.extend(analysis_results)
            self.processed_count += len(quotes_inputs)

            logger.info("Completed recent quotes analysis", imported=len(quotes_inputs), analyzed=len(analysis_results))

            return self._create_summary(start_time, len(quotes_inputs), analysis_results)

        except Exception as e:
            logger.error("Failed to import and analyze recent quotes", error=str(e), limit=limit, days=days)
            raise

    async def import_and_analyze_user_quotes(self, username: str, limit: int = 50) -> dict:
        """Import and analyze quotes from a specific user.

        Args:
            username: Username to analyze quotes for
            limit: Maximum number of quotes to import

        Returns:
            Analysis summary dictionary
        """
        logger.info("Starting user quotes import and analysis", username=username, limit=limit)

        start_time = datetime.utcnow()

        try:
            # Import quotes for user
            async with ElsydeonQuotesClient() as client:
                quotes_data = await client.get_quotes_by_user(username=username, limit=limit)

            if not quotes_data:
                logger.warning("No quotes found for user", username=username)
                return self._create_summary(start_time, 0, [])

            # Process quotes into text analysis format
            processor = QuotesDataProcessor()
            quotes_inputs = processor.process_quotes_batch(quotes_data)

            # Analyze quotes
            analysis_results = await self.text_analysis_service.batch_analyze(quotes_inputs)

            # Store results
            self.analysis_results.extend(analysis_results)
            self.processed_count += len(quotes_inputs)

            logger.info(
                "Completed user quotes analysis",
                username=username,
                imported=len(quotes_inputs),
                analyzed=len(analysis_results),
            )

            return self._create_summary(start_time, len(quotes_inputs), analysis_results)

        except Exception as e:
            logger.error("Failed to import and analyze user quotes", username=username, error=str(e))
            raise

    async def bulk_import_and_analyze(self, batch_size: int = 50, max_batches: int | None = None) -> dict:
        """Bulk import and analyze all quotes for comprehensive vocabulary building.

        Args:
            batch_size: Number of quotes to process per batch
            max_batches: Optional limit on number of batches to process

        Returns:
            Analysis summary dictionary
        """
        logger.info("Starting bulk quotes import and analysis", batch_size=batch_size, max_batches=max_batches)

        start_time = datetime.utcnow()
        total_imported = 0
        total_analyzed = 0
        batch_count = 0

        try:
            async for quotes_batch in bulk_import_all_quotes(batch_size=batch_size):
                if max_batches and batch_count >= max_batches:
                    logger.info("Reached maximum batch limit", max_batches=max_batches)
                    break

                batch_count += 1

                # Analyze batch
                analysis_results = await self.text_analysis_service.batch_analyze(quotes_batch)

                # Store results
                self.analysis_results.extend(analysis_results)
                total_imported += len(quotes_batch)
                total_analyzed += len(analysis_results)

                logger.debug(
                    "Processed quotes batch",
                    batch=batch_count,
                    imported=len(quotes_batch),
                    analyzed=len(analysis_results),
                )

                # Brief pause between batches to avoid overwhelming the system
                await asyncio.sleep(0.1)

            self.processed_count += total_imported

            logger.info(
                "Completed bulk quotes analysis",
                batches=batch_count,
                total_imported=total_imported,
                total_analyzed=total_analyzed,
            )

            return self._create_summary(start_time, total_imported, self.analysis_results[-total_analyzed:])

        except Exception as e:
            logger.error("Failed during bulk import and analysis", error=str(e), batches_processed=batch_count)
            raise

    def get_vocabulary_insights(self) -> dict:
        """Extract vocabulary insights from analyzed quotes.

        Returns:
            Dictionary with vocabulary statistics and insights
        """
        if not self.analysis_results:
            return {"error": "No analysis results available"}

        # Aggregate vocabulary data
        all_vocabulary = []
        all_potential_vocabulary = []
        community_scores = []
        username_mentions = []

        for result in self.analysis_results:
            if result.error:
                continue

            all_vocabulary.extend(result.vocabulary_matches)
            all_potential_vocabulary.extend(result.potential_vocabulary)
            community_scores.append(result.community_score)
            username_mentions.extend(result.username_mentions)

        # Calculate statistics
        vocabulary_frequency = {}
        for vocab in all_vocabulary:
            vocabulary_frequency[vocab] = vocabulary_frequency.get(vocab, 0) + 1

        potential_frequency = {}
        for vocab in all_potential_vocabulary:
            potential_frequency[vocab] = potential_frequency.get(vocab, 0) + 1

        # Sort by frequency
        top_vocabulary = sorted(vocabulary_frequency.items(), key=lambda x: x[1], reverse=True)[:20]
        top_potential = sorted(potential_frequency.items(), key=lambda x: x[1], reverse=True)[:20]

        # Username analysis
        username_frequency = {}
        for username in username_mentions:
            username_frequency[username] = username_frequency.get(username, 0) + 1

        top_usernames = sorted(username_frequency.items(), key=lambda x: x[1], reverse=True)[:10]

        return {
            "total_quotes_analyzed": len([r for r in self.analysis_results if not r.error]),
            "total_errors": len([r for r in self.analysis_results if r.error]),
            "average_community_score": sum(community_scores) / len(community_scores) if community_scores else 0,
            "vocabulary_insights": {
                "total_vocabulary_matches": len(all_vocabulary),
                "unique_vocabulary": len(vocabulary_frequency),
                "top_vocabulary": top_vocabulary,
                "total_potential_vocabulary": len(all_potential_vocabulary),
                "unique_potential": len(potential_frequency),
                "top_potential": top_potential,
            },
            "username_insights": {
                "total_mentions": len(username_mentions),
                "unique_users": len(username_frequency),
                "top_mentioned_users": top_usernames,
            },
        }

    def _create_summary(
        self, start_time: datetime, imported_count: int, analysis_results: list[TextAnalysisOutput]
    ) -> dict:
        """Create analysis summary dictionary.

        Args:
            start_time: When the operation started
            imported_count: Number of quotes imported
            analysis_results: Analysis results

        Returns:
            Summary dictionary
        """
        processing_time = (datetime.utcnow() - start_time).total_seconds()
        successful_analyses = len([r for r in analysis_results if not r.error])
        failed_analyses = len([r for r in analysis_results if r.error])

        # Extract some quick stats
        total_vocabulary = sum(len(r.vocabulary_matches) for r in analysis_results if not r.error)
        total_potential = sum(len(r.potential_vocabulary) for r in analysis_results if not r.error)
        avg_community_score = (
            sum(r.community_score for r in analysis_results if not r.error) / successful_analyses
            if successful_analyses > 0
            else 0
        )

        return {
            "import_summary": {
                "quotes_imported": imported_count,
                "quotes_analyzed": successful_analyses,
                "analysis_failures": failed_analyses,
                "processing_time_seconds": round(processing_time, 2),
            },
            "vocabulary_summary": {
                "total_vocabulary_matches": total_vocabulary,
                "total_potential_vocabulary": total_potential,
                "average_community_score": round(avg_community_score, 3),
            },
            "completed_at": datetime.utcnow().isoformat(),
        }


# Convenience functions for external use


async def analyze_recent_quotes(limit: int = 100, days: int = 30) -> dict:
    """Convenience function to analyze recent quotes.

    Args:
        limit: Maximum number of quotes to analyze
        days: Number of days back to search

    Returns:
        Analysis summary dictionary
    """
    integration = QuotesAnalysisIntegration()
    return await integration.import_and_analyze_recent_quotes(limit=limit, days=days)


async def analyze_user_quotes(username: str, limit: int = 50) -> dict:
    """Convenience function to analyze quotes from a specific user.

    Args:
        username: Username to analyze quotes for
        limit: Maximum number of quotes to analyze

    Returns:
        Analysis summary dictionary
    """
    integration = QuotesAnalysisIntegration()
    return await integration.import_and_analyze_user_quotes(username=username, limit=limit)


async def build_vocabulary_from_quotes(batch_size: int = 50, max_batches: int | None = None) -> dict:
    """Build community vocabulary from historical quotes data.

    Args:
        batch_size: Number of quotes to process per batch
        max_batches: Optional limit on number of batches

    Returns:
        Vocabulary insights dictionary
    """
    integration = QuotesAnalysisIntegration()

    # Import and analyze quotes
    summary = await integration.bulk_import_and_analyze(batch_size=batch_size, max_batches=max_batches)

    # Get vocabulary insights
    insights = integration.get_vocabulary_insights()

    # Combine summary and insights
    return {**summary, "vocabulary_insights": insights}
