#!/usr/bin/env python3
"""Test run script for phononmaser without Whisper model."""
import asyncio
import os

# Set environment variables for testing
os.environ["PHONONMASER_PORT"] = "8889"
os.environ["PHONONMASER_HEALTH_PORT"] = "8890"
os.environ["PHONONMASER_HOST"] = "localhost"

# Mock the Whisper model path for testing
os.environ["WHISPER_MODEL_PATH"] = "/tmp/test_model.bin"

# Create a mock model file
import tempfile
with open("/tmp/test_model.bin", "wb") as f:
    f.write(b"mock model data")

try:
    from src.main import main
    asyncio.run(main())
except KeyboardInterrupt:
    print("\nShutdown requested")