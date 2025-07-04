#!/bin/bash

# Pre-commit hooks setup script for Landale project
# This script sets up pre-commit hooks for all languages used in the project

set -e

echo "🔧 Setting up pre-commit hooks for Landale project..."

# Check if pre-commit is installed
if ! command -v pre-commit &> /dev/null; then
    echo "❌ pre-commit is not installed. Please install it first:"
    echo "   uv tool install pre-commit"
    echo "   or"
    echo "   uv pip install -r requirements-dev.txt"
    exit 1
fi

# Install Python dev dependencies if requirements-dev.txt exists
if [ -f "requirements-dev.txt" ]; then
    echo "📦 Installing Python development dependencies..."
    uv pip install -r requirements-dev.txt
fi

# Install pre-commit hooks
echo "🔗 Installing pre-commit hooks..."
pre-commit install
pre-commit install --hook-type pre-push

# Run pre-commit on all files to ensure everything is working
echo "🧪 Running pre-commit on all files to test setup..."
pre-commit run --all-files || {
    echo "⚠️  Some hooks failed, but this is expected on first run."
    echo "   The hooks will fix many issues automatically."
    echo "   You may need to stage the changes and run again."
}

echo "✅ Pre-commit hooks setup complete!"
echo ""
echo "📝 Usage:"
echo "   • Hooks will run automatically on git commit"
echo "   • Run manually: bun run pre-commit:run"
echo "   • Run on staged files: bun run pre-commit:run-staged"
echo "   • Update hooks: bun run pre-commit:update"
echo ""
echo "🏃 For Elixir hooks to work, ensure you have Elixir/Mix installed:"
echo "   • Install Elixir: https://elixir-lang.org/install.html"
echo "   • Or use asdf/mise for version management"
echo ""
echo "💡 If you encounter issues with specific hooks, you can:"
echo "   • Skip them temporarily: git commit --no-verify"
echo "   • Disable specific hooks by editing .pre-commit-config.yaml"