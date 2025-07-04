#!/bin/bash
set -e

# Nurvus Deployment Script
# Universal deployment script for all machines

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MACHINE_NAME="${1:-$(hostname -s)}"
TARGET_DIR="${2:-/opt/nurvus}"
SERVICE_USER="${3:-bryan}"

echo "🚀 Deploying Nurvus to $MACHINE_NAME"
echo "   Project: $PROJECT_DIR"
echo "   Target: $TARGET_DIR"
echo "   User: $SERVICE_USER"

# Check if running as root for system installation
if [[ $EUID -eq 0 ]]; then
    echo "⚠️  Running as root - will install system-wide"
    SUDO=""
else
    echo "👤 Running as user - will use sudo for system operations"
    SUDO="sudo"
fi

# Step 1: Build release
echo "📦 Building release..."
cd "$PROJECT_DIR"
export MIX_ENV=prod
mix deps.get --only prod
mix compile
mix release

# Step 2: Create target directory
echo "📁 Creating target directory..."
$SUDO mkdir -p "$TARGET_DIR"
$SUDO mkdir -p "$TARGET_DIR/config"
$SUDO mkdir -p "/var/log/nurvus"

# Step 3: Copy release
echo "📋 Copying release files..."
$SUDO cp -r _build/prod/rel/nurvus/* "$TARGET_DIR/"

# Step 4: Copy machine-specific configuration
if [[ -f "config/${MACHINE_NAME}.json" ]]; then
    echo "⚙️  Copying ${MACHINE_NAME} configuration..."
    $SUDO cp "config/${MACHINE_NAME}.json" "$TARGET_DIR/config/"
    $SUDO cp "config/${MACHINE_NAME}.json" "$TARGET_DIR/config/processes.json"
else
    echo "⚠️  No specific config for $MACHINE_NAME, using default"
    if [[ -f "config/processes.json" ]]; then
        $SUDO cp "config/processes.json" "$TARGET_DIR/config/"
    fi
fi

# Step 5: Set ownership
echo "👤 Setting ownership..."
$SUDO chown -R "$SERVICE_USER:$SERVICE_USER" "$TARGET_DIR"
$SUDO chown -R "$SERVICE_USER:$SERVICE_USER" "/var/log/nurvus"

# Step 6: Install systemd service (Unix only)
if command -v systemctl >/dev/null 2>&1; then
    echo "🔧 Installing systemd service..."
    
    # Choose machine-specific service file if available
    if [[ -f "deployment/systemd/nurvus-${MACHINE_NAME}.service" ]]; then
        SERVICE_FILE="deployment/systemd/nurvus-${MACHINE_NAME}.service"
        SERVICE_NAME="nurvus-${MACHINE_NAME}"
    else
        SERVICE_FILE="deployment/systemd/nurvus.service"
        SERVICE_NAME="nurvus"
    fi
    
    $SUDO cp "$SERVICE_FILE" "/etc/systemd/system/${SERVICE_NAME}.service"
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable "$SERVICE_NAME"
    
    echo "✅ Service installed as $SERVICE_NAME"
    echo "   Start: sudo systemctl start $SERVICE_NAME"
    echo "   Status: sudo systemctl status $SERVICE_NAME"
    echo "   Logs: sudo journalctl -u $SERVICE_NAME -f"
else
    echo "⚠️  systemctl not found, skipping service installation"
fi

# Step 7: Create helper scripts
echo "📝 Creating helper scripts..."
cat > "$TARGET_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./bin/nurvus start
EOF

cat > "$TARGET_DIR/stop.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./bin/nurvus stop
EOF

cat > "$TARGET_DIR/status.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./bin/nurvus pid
EOF

chmod +x "$TARGET_DIR"/*.sh

# Step 8: Test installation
echo "🧪 Testing installation..."
if [[ -x "$TARGET_DIR/bin/nurvus" ]]; then
    echo "✅ Binary is executable"
else
    echo "❌ Binary not found or not executable"
    exit 1
fi

# Step 9: Display next steps
echo ""
echo "🎉 Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Test the installation:"
echo "   $TARGET_DIR/bin/nurvus start"
echo "   curl http://localhost:4001/health"
echo "   $TARGET_DIR/bin/nurvus stop"
echo ""

if command -v systemctl >/dev/null 2>&1; then
    echo "2. Start the service:"
    echo "   sudo systemctl start $SERVICE_NAME"
    echo ""
    echo "3. Check status:"
    echo "   sudo systemctl status $SERVICE_NAME"
    echo "   curl http://localhost:4001/health"
fi

echo ""
echo "📚 See DEPLOYMENT.md for more information"