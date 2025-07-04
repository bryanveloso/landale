#!/bin/bash
# Setup Python services with uv

set -e  # Exit on error

echo "Setting up Python services..."

# Navigate to project root
cd "$(dirname "$0")/.."

# Setup phononmaser
echo "Setting up phononmaser..."
cd apps/phononmaser
uv venv
uv pip sync

# Setup analysis service
echo "Setting up analysis service..."
cd ../analysis
uv venv
uv pip sync

# Return to root
cd ../..

echo "Python services setup complete!"
echo ""
echo "To run with Supervisor:"
echo "  ./bin/landale-supervisor start"
echo ""
echo "To check status:"
echo "  ./bin/landale-supervisor status"
