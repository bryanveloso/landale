#!/usr/bin/env bash
# Build script for Nurvus that automatically increments version

set -e

echo "🔨 Building Nurvus with automatic version increment..."

# Always increment version before building
echo "📈 Incrementing version..."
mix increment_version

# Run the release build
echo "🚀 Building release..."
MIX_ENV=prod mix release --overwrite

echo "✅ Build complete!"