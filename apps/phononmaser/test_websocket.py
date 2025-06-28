#!/usr/bin/env python3
"""Test WebSocket server without Whisper model."""
import asyncio
import logging
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Set minimal environment
os.environ["PHONONMASER_PORT"] = "8889"
os.environ["PHONONMASER_HEALTH_PORT"] = "8890"

async def test_server():
    """Test just the WebSocket server component."""
    from src.websocket_server import PhononmaserServer
    
    # Create a minimal audio processor mock
    class MockAudioProcessor:
        def __init__(self):
            self.is_running = False
            self.is_transcribing = False
            self.buffer = type('obj', (object,), {'total_size': 0})()
            self.transcription_callback = None
            
        async def start(self):
            self.is_running = True
            
        async def stop(self):
            self.is_running = False
            
        def add_chunk(self, chunk):
            pass
    
    # Create and start server
    processor = MockAudioProcessor()
    server = PhononmaserServer(processor, port=8889)
    
    print("Starting WebSocket server on ws://localhost:8889")
    print("Press Ctrl+C to stop")
    
    await server.start()
    
    try:
        # Keep running
        while True:
            await asyncio.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        await server.stop()

if __name__ == "__main__":
    asyncio.run(test_server())