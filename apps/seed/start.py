#!/usr/bin/env python3
"""Startup script for the SEED intelligence service."""

import asyncio
import sys

from src.main import main

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down...")
        sys.exit(0)
