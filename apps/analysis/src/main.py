"""Main entry point for the analysis service."""
import asyncio
import logging
import os
import signal
from typing import Optional

from dotenv import load_dotenv

from .websocket_client import PhononmaserClient, ServerClient
from .lms_client import LMSClient
from .correlator import StreamCorrelator
from .events import TranscriptionEvent, ChatMessage, EmoteEvent, AnalysisResult

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class AnalysisService:
    """Main analysis service that coordinates all components."""
    
    def __init__(self):
        # Configuration from environment
        self.phononmaser_url = os.getenv("PHONONMASER_URL", "ws://localhost:8889")
        self.server_url = os.getenv("SERVER_URL", "ws://localhost:8080/ws")
        self.lms_url = os.getenv("LMS_API_URL", "http://zelan:1234/v1")
        self.lms_model = os.getenv("LMS_MODEL", "dolphin-2.9.3-llama-3-8b")
        
        # Components
        self.phononmaser_client = PhononmaserClient(self.phononmaser_url)
        self.server_client = ServerClient(self.server_url)
        self.lms_client = LMSClient(self.lms_url, self.lms_model)
        self.correlator: Optional[StreamCorrelator] = None
        
        # State
        self.running = False
        self.tasks = []
        
    async def start(self):
        """Start the analysis service."""
        logger.info("Starting analysis service...")
        
        # Initialize LMS client
        await self.lms_client.__aenter__()
        
        # Initialize correlator
        self.correlator = StreamCorrelator(self.lms_client)
        
        # Register event handlers
        self.phononmaser_client.on_transcription(self._handle_transcription)
        self.server_client.on_chat_message(self._handle_chat_message)
        self.server_client.on_emote(self._handle_emote)
        self.correlator.on_analysis(self._handle_analysis_result)
        
        # Connect to services
        try:
            await self.phononmaser_client.connect()
            await self.server_client.connect()
        except Exception as e:
            logger.error(f"Failed to connect to services: {e}")
            raise
            
        self.running = True
        
        # Start listening tasks
        self.tasks = [
            asyncio.create_task(self.phononmaser_client.listen()),
            asyncio.create_task(self.server_client.listen()),
            asyncio.create_task(self.correlator.periodic_analysis_loop()),
            asyncio.create_task(self._health_check_loop())
        ]
        
        logger.info("Analysis service started successfully")
        
    async def stop(self):
        """Stop the analysis service."""
        logger.info("Stopping analysis service...")
        self.running = False
        
        # Cancel tasks
        for task in self.tasks:
            task.cancel()
            
        # Wait for tasks to complete
        await asyncio.gather(*self.tasks, return_exceptions=True)
        
        # Disconnect clients
        await self.phononmaser_client.disconnect()
        await self.server_client.disconnect()
        await self.lms_client.__aexit__(None, None, None)
        
        logger.info("Analysis service stopped")
        
    async def _handle_transcription(self, event: TranscriptionEvent):
        """Handle transcription events from phononmaser."""
        logger.debug(f"Transcription: {event.text}")
        
        if self.correlator:
            await self.correlator.add_transcription(event)
            
    async def _handle_chat_message(self, event: ChatMessage):
        """Handle chat message events from server."""
        logger.debug(f"Chat: {event.username}: {event.message}")
        
        if self.correlator:
            await self.correlator.add_chat_message(event)
            
    async def _handle_emote(self, event: EmoteEvent):
        """Handle emote events from server."""
        logger.debug(f"Emote: {event.username} used {event.emote_name}")
        
        if self.correlator:
            await self.correlator.add_emote(event)
            
    async def _handle_analysis_result(self, result: AnalysisResult):
        """Handle analysis results from correlator."""
        logger.info(f"Analysis result: {result.sentiment} sentiment, momentum: {result.stream_momentum}")
        
        # Log detailed results
        logger.info(f"Topics: {result.topics}")
        logger.info(f"Patterns: {result.patterns}")
        if result.chat_velocity:
            logger.info(f"Chat velocity: {result.chat_velocity:.1f} msg/min")
        if result.emote_frequency:
            logger.info(f"Top emotes: {list(result.emote_frequency.keys())[:5]}")
            
        # TODO: Future enhancements
        # - Send to server via WebSocket for overlay display
        # - Store in database for historical analysis
        # - Trigger overlay effects based on patterns
        # - Send notifications for significant events
            
    async def _health_check_loop(self):
        """Periodic health check."""
        while self.running:
            await asyncio.sleep(60)  # Every minute
            logger.info("Health check: Service is running")
            

async def main():
    """Main entry point."""
    service = AnalysisService()
    
    # Handle shutdown signals
    loop = asyncio.get_event_loop()
    
    def handle_shutdown():
        logger.info("Received shutdown signal")
        asyncio.create_task(service.stop())
        
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, handle_shutdown)
        
    try:
        await service.start()
        
        # Keep running until stopped
        while service.running:
            await asyncio.sleep(1)
            
    except Exception as e:
        logger.error(f"Service error: {e}")
        await service.stop()
        

if __name__ == "__main__":
    asyncio.run(main())