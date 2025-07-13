#!/usr/bin/env python3
"""Run phononmaser locally for development."""

import subprocess
import sys

# Run as module to ensure imports work correctly
subprocess.run([sys.executable, "-m", "src.main"])
