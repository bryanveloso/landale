"""WebSocket interface for RAG queries."""

from typing import TYPE_CHECKING

from shared.logger import get_logger

if TYPE_CHECKING:
    from .rag_handler import RAGHandler

logger = get_logger(__name__)


class RAGWebSocketHandler:
    """Handles RAG queries via WebSocket messages."""

    def __init__(self, rag_handler: "RAGHandler", server_client):
        """
        Initialize RAG WebSocket handler.

        Args:
            rag_handler: The RAG handler instance
            server_client: The WebSocket client to send responses through
        """
        self.rag_handler = rag_handler
        self.server_client = server_client

    async def handle_query(self, message: dict):
        """
        Handle incoming RAG query from WebSocket.

        Expected message format:
        {
            "type": "rag_query",
            "question": "How many subs do I have?",
            "time_window_hours": 24,  # optional
            "correlation_id": "abc123"  # optional
        }
        """
        try:
            question = message.get("question", "").strip()
            if not question:
                await self._send_error("Question is required", message.get("correlation_id"))
                return

            time_window = message.get("time_window_hours", 24)
            correlation_id = message.get("correlation_id", "")

            logger.info(f"Processing RAG query via WebSocket: {question[:100]}...")

            # Process the query
            result = await self.rag_handler.query(question, time_window)

            # Send response back via WebSocket
            response = {
                "type": "rag_response",
                "correlation_id": correlation_id,
                **result,
            }

            await self.server_client.send_json(response)
            logger.info(f"RAG response sent for query: {question[:50]}...")

        except Exception as e:
            logger.error(f"Error processing RAG query via WebSocket: {e}")
            await self._send_error(str(e), message.get("correlation_id"))

    async def _send_error(self, error_message: str, correlation_id: str = ""):
        """Send error response via WebSocket."""
        try:
            response = {
                "type": "rag_error",
                "correlation_id": correlation_id,
                "success": False,
                "error": error_message,
            }
            await self.server_client.send_json(response)
        except Exception as e:
            logger.error(f"Failed to send error response: {e}")


def setup_rag_websocket_handlers(server_client, rag_handler: "RAGHandler"):
    """
    Set up WebSocket event handlers for RAG queries.

    This integrates RAG queries into the existing WebSocket event system.
    """
    handler = RAGWebSocketHandler(rag_handler, server_client)

    # Register handler for rag_query events
    server_client.on_message("rag_query", handler.handle_query)

    logger.info("RAG WebSocket handlers registered for 'rag_query' events")

    return handler
