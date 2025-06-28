#!/bin/bash
# Setup Python services with uv

echo "Setting up Python services..."

# Setup phononmaser
echo "Setting up phononmaser..."
cd apps/phononmaser
uv venv
uv pip install -r requirements.txt

# Setup analysis service
echo "Setting up analysis service..."
cd ../analysis
uv venv
uv pip install -r requirements.txt

echo "Python services setup complete!"
echo ""
echo "To run with PM2:"
echo "  cd ~/Code/bryanveloso/landale"
echo "  pm2 start ecosystem/zelan.config.cjs"