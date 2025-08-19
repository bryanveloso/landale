#!/usr/bin/env python3
"""Startup script for the SEED intelligence service."""

import asyncio
import sys

from shared.logger import configure_json_logging, get_logger

from src.main import main

# Configure structured JSON logging
configure_json_logging(service_name="seed", component="startup")
logger = get_logger(__name__)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        sys.exit(0)
