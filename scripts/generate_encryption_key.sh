#!/bin/bash

# Script to generate and configure encryption key for Landale token vault
# Implements AES-256-GCM encryption as per security standards

set -e

echo "🔐 Generating encryption key for Landale Token Vault"
echo "=================================================="

# Generate a 256-bit (32 byte) key and base64 encode it
KEY=$(openssl rand -base64 32)

echo ""
echo "Generated encryption key (keep this secret!):"
echo "---------------------------------------------"
echo "$KEY"
echo ""

# Check if .env file exists
ENV_FILE="apps/server/.env"
ENV_EXAMPLE="apps/server/.env.example"

# Update or add to .env.example
if [ -f "$ENV_EXAMPLE" ]; then
    if grep -q "LANDALE_ENCRYPTION_KEY" "$ENV_EXAMPLE"; then
        echo "✅ LANDALE_ENCRYPTION_KEY already in .env.example"
    else
        echo "" >> "$ENV_EXAMPLE"
        echo "# Token encryption key (generate with scripts/generate_encryption_key.sh)" >> "$ENV_EXAMPLE"
        echo "LANDALE_ENCRYPTION_KEY=your-base64-encoded-256-bit-key-here" >> "$ENV_EXAMPLE"
        echo "✅ Added LANDALE_ENCRYPTION_KEY to .env.example"
    fi
fi

# Check if .env file exists
if [ -f "$ENV_FILE" ]; then
    echo ""
    echo "Found existing .env file at $ENV_FILE"

    # Check if key already exists
    if grep -q "LANDALE_ENCRYPTION_KEY" "$ENV_FILE"; then
        echo "⚠️  WARNING: LANDALE_ENCRYPTION_KEY already exists in .env"
        echo "   Current value will not be overwritten."
        echo "   To use the new key, manually update the .env file"
    else
        echo "LANDALE_ENCRYPTION_KEY=$KEY" >> "$ENV_FILE"
        echo "✅ Added LANDALE_ENCRYPTION_KEY to .env"
    fi
else
    echo ""
    echo "Creating new .env file at $ENV_FILE"
    echo "# Auto-generated encryption key for token vault" > "$ENV_FILE"
    echo "LANDALE_ENCRYPTION_KEY=$KEY" >> "$ENV_FILE"
    echo "✅ Created .env with LANDALE_ENCRYPTION_KEY"
fi

echo ""
echo "📋 Next steps:"
echo "1. If using Docker, add to docker-compose.yml environment section:"
echo "   LANDALE_ENCRYPTION_KEY=\${LANDALE_ENCRYPTION_KEY}"
echo ""
echo "2. For production, store this key securely in:"
echo "   - AWS Secrets Manager"
echo "   - Environment variable on the production machine"
echo "   - CI/CD secret storage"
echo ""
echo "3. Test the encryption:"
echo "   cd apps/server && mix deps.get && iex -S mix"
echo "   > Server.TokenVault.encrypt(\"test\")"
echo ""
echo "⚠️  SECURITY REMINDER:"
echo "   - Never commit the .env file to git"
echo "   - Never log or print the encryption key"
echo "   - Rotate the key periodically"
echo "   - Use different keys for dev/staging/production"
