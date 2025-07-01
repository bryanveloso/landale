#!/bin/bash
set -e

echo "Building Elixir cluster releases..."

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf _build/prod/rel

# Build controller release (for zelan - Mac Studio)
echo "Building controller release for zelan (macOS)..."
MIX_ENV=prod mix release server

# Build Linux worker release (for saya/alys)
echo "Building Linux worker release..."
MIX_ENV=prod mix release worker

# Note: Windows worker needs to be built on Windows machine or cross-compiled
echo "Windows worker release needs to be built on Windows machine"
echo "Use: MIX_ENV=prod mix release worker_windows"

echo "Release build complete!"
echo ""
echo "Releases are available in:"
echo "  Controller (zelan): _build/prod/rel/server/"
echo "  Worker (Linux):     _build/prod/rel/worker/"
echo ""
echo "Next steps:"
echo "1. Copy releases to respective machines"
echo "2. Set environment variables"
echo "3. Run cluster formation test"