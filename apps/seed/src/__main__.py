"""Entry point for running analysis service as a module."""

import asyncio

from main import main

if __name__ == "__main__":
    asyncio.run(main())
