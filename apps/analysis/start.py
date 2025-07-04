#!/usr/bin/env python3
"""Startup script for the analysis service."""
import sys
import asyncio
from src.main import main

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down...")
        sys.exit(0)
