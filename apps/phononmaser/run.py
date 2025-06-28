#!/usr/bin/env python3
"""Run phononmaser locally for development."""
import asyncio
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from main import main

if __name__ == "__main__":
    asyncio.run(main())