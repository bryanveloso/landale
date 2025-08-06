#!/bin/bash

# macOS LaunchAgent Installation Script for Nurvus
# This script installs Nurvus as a user LaunchAgent that starts automatically

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
PLIST_NAME="com.bryanveloso.nurvus.plist"
PLIST_SOURCE="$(dirname "$0")/$PLIST_NAME"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"
NURVUS_BINARY="$HOME/.local/bin/nurvus"
LOG_DIR="$HOME/Library/Logs/nurvus"

# Check if we're on macOS
check_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This script is for macOS only."
        log_info "For Linux, use the systemd service instead."
        exit 1
    fi
}

# Check if Nurvus binary exists
check_binary() {
    if [[ ! -f "$NURVUS_BINARY" ]]; then
        log_error "Nurvus binary not found at $NURVUS_BINARY"
        log_info "Please run the setup-macos.sh script first to install Nurvus"
        exit 1
    fi

    if [[ ! -x "$NURVUS_BINARY" ]]; then
        log_error "Nurvus binary is not executable"
        log_info "Run: chmod +x $NURVUS_BINARY"
        exit 1
    fi

    log_success "Found Nurvus binary at $NURVUS_BINARY"
}

# Create log directory
create_log_dir() {
    if [[ ! -d "$LOG_DIR" ]]; then
        log_info "Creating log directory: $LOG_DIR"
        mkdir -p "$LOG_DIR"
    fi
    log_success "Log directory ready: $LOG_DIR"
}

# Install LaunchAgent
install_plist() {
    if [[ ! -f "$PLIST_SOURCE" ]]; then
        log_error "LaunchAgent plist not found at $PLIST_SOURCE"
        exit 1
    fi

    # Create LaunchAgents directory if it doesn't exist
    mkdir -p "$(dirname "$PLIST_DEST")"

    # Copy plist file with path substitution
    log_info "Installing LaunchAgent to $PLIST_DEST"
    sed "s|__HOME__|$HOME|g" "$PLIST_SOURCE" > "$PLIST_DEST"

    # Fix ownership
    chmod 644 "$PLIST_DEST"

    log_success "LaunchAgent installed successfully"
}

# Load LaunchAgent
load_service() {
    log_info "Loading Nurvus LaunchAgent..."

    # Unload if already loaded (ignore errors)
    launchctl unload "$PLIST_DEST" 2>/dev/null || true

    # Load the service
    if launchctl load "$PLIST_DEST"; then
        log_success "Nurvus LaunchAgent loaded successfully"

        # Wait a moment for startup
        sleep 2

        # Check if it's running
        if launchctl list | grep -q "com.bryanveloso.nurvus"; then
            log_success "Nurvus is now running as a background service"
            log_info "Web interface available at: http://localhost:4001"
        else
            log_warning "Service loaded but may not be running. Check logs:"
            log_info "Logs: $LOG_DIR/stdout.log and $LOG_DIR/stderr.log"
        fi
    else
        log_error "Failed to load LaunchAgent"
        exit 1
    fi
}

# Show status and management commands
show_management_info() {
    echo
    echo "=================================================="
    echo "      Nurvus LaunchAgent Management"
    echo "=================================================="
    echo
    echo "Service Status:"
    echo "  launchctl list | grep nurvus"
    echo
    echo "View Logs:"
    echo "  tail -f $LOG_DIR/stdout.log"
    echo "  tail -f $LOG_DIR/stderr.log"
    echo
    echo "Manual Control:"
    echo "  launchctl unload $PLIST_DEST    # Stop service"
    echo "  launchctl load $PLIST_DEST      # Start service"
    echo
    echo "Remove Service:"
    echo "  launchctl unload $PLIST_DEST"
    echo "  rm $PLIST_DEST"
    echo
    echo "Web Interface:"
    echo "  http://localhost:4001"
    echo
    echo "Configuration:"
    echo "  ~/.config/nurvus/processes.json"
    echo "=================================================="
}

# Main installation function
main() {
    echo "=================================================="
    echo "      Nurvus macOS LaunchAgent Installer"
    echo "=================================================="
    echo

    # Pre-flight checks
    check_macos
    check_binary
    create_log_dir

    # Install and start service
    install_plist
    load_service

    # Show management information
    show_management_info

    log_success "Installation complete!"
    log_info "Nurvus will now start automatically when you log in."
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Nurvus macOS LaunchAgent Installer"
        echo
        echo "This script installs Nurvus as a user LaunchAgent that:"
        echo "  - Starts automatically when you log in"
        echo "  - Runs in the background"
        echo "  - Restarts automatically if it crashes"
        echo "  - Logs to ~/Library/Logs/nurvus/"
        echo
        echo "Prerequisites:"
        echo "  - Nurvus binary installed at ~/.local/bin/nurvus"
        echo "  - Run setup-macos.sh first if not already done"
        echo
        echo "Usage:"
        echo "  $0              Install and start LaunchAgent"
        echo "  $0 --help      Show this help"
        echo "  $0 --uninstall Remove LaunchAgent"
        echo
        exit 0
        ;;
    --uninstall)
        log_info "Uninstalling Nurvus LaunchAgent..."
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
        rm -f "$PLIST_DEST"
        log_success "LaunchAgent removed successfully"
        exit 0
        ;;
esac

# Run main installation
main
