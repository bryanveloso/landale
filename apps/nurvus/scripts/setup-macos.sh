#!/bin/bash

# macOS Setup Script for Nurvus
# This script should be included in the tar.gz packages for macOS machines (Zelan, Saya)
# It handles Gatekeeper bypass and installation to ~/.local/bin

set -e

# Configuration
BINARY_TEST_TIMEOUT=5

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

# Find the Nurvus binary in current directory
find_nurvus_binary() {
    local binary_path=""
    
    # Look for various possible names
    for name in "nurvus_macos" "nurvus" "nurvus_darwin"; do
        if [[ -f "$name" ]]; then
            binary_path="$name"
            break
        fi
    done
    
    if [[ -z "$binary_path" ]]; then
        log_error "Could not find Nurvus binary in current directory."
        log_info "Expected one of: nurvus_macos, nurvus, nurvus_darwin"
        log_info "Available files:"
        ls -la
        exit 1
    fi
    
    echo "$binary_path"
}

# Check if we're on macOS
check_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This script is for macOS only."
        log_info "For other platforms, just run the binary directly."
        exit 1
    fi
    
    # Check for Apple Silicon
    if [[ "$(uname -m)" != "arm64" && "$(uname -m)" != "aarch64" ]]; then
        log_warning "This binary is built for Apple Silicon (M1/M2/M3)."
        log_warning "Intel Macs are not officially supported."
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Remove macOS quarantine attributes
remove_quarantine() {
    local file="$1"
    
    log_info "Removing macOS quarantine attributes from $file..."
    
    if xattr -c "$file" 2>/dev/null; then
        log_success "Quarantine attributes removed successfully"
        return 0
    else
        log_warning "Could not remove quarantine attributes automatically"
        log_info "You may need to manually allow Nurvus in System Settings"
        return 1
    fi
}

# Make binary executable
make_executable() {
    local file="$1"
    
    log_info "Making $file executable..."
    
    if chmod +x "$file"; then
        log_success "Binary is now executable"
    else
        log_error "Failed to make binary executable"
        exit 1
    fi
}

# Test if binary runs
test_binary() {
    local file="$1"
    
    log_info "Testing if binary runs..."
    
    if timeout ${BINARY_TEST_TIMEOUT}s "./$file" --help >/dev/null 2>&1; then
        log_success "Binary test passed! Nurvus is ready to use."
        return 0
    else
        log_warning "Binary test failed or requires manual security approval"
        return 1
    fi
}

# Install to ~/.local/bin
install_to_local_bin() {
    local source_file="$1"
    local install_dir="$HOME/.local/bin"
    local install_path="$install_dir/nurvus"
    
    # Ask user if they want to install to ~/.local/bin
    echo
    read -p "Do you want to install Nurvus to ~/.local/bin for system-wide access? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Skipping installation to ~/.local/bin"
        return 0
    fi
    
    # Create directory if it doesn't exist
    if [[ ! -d "$install_dir" ]]; then
        log_info "Creating $install_dir..."
        mkdir -p "$install_dir"
    fi
    
    # Check if already installed
    if [[ -f "$install_path" ]]; then
        log_warning "Nurvus is already installed in ~/.local/bin"
        read -p "Do you want to update it? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi
    
    log_info "Installing to $install_path..."
    
    # Copy and setup
    cp "$source_file" "$install_path"
    chmod +x "$install_path"
    remove_quarantine "$install_path"
    
    log_success "Installed to ~/.local/bin/nurvus"
    
    # Check PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warning "~/.local/bin is not in your PATH"
        log_info "Add this line to your shell profile (~/.zshrc, ~/.bash_profile, etc.):"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        log_info "Then run: source ~/.zshrc (or restart your terminal)"
    else
        log_success "~/.local/bin is already in your PATH"
        log_info "You can now run 'nurvus' from anywhere!"
    fi
}

# Show manual bypass instructions
show_manual_instructions() {
    echo
    log_info "If you see security warnings when running Nurvus:"
    echo
    echo "METHOD 1 - System Settings (Recommended):"
    echo "1. Try to run Nurvus (you'll see a security warning)"
    echo "2. Open System Settings → Privacy & Security"
    echo "3. Scroll to Security section"
    echo "4. Click 'Allow Anyway' next to the Nurvus warning"
    echo "5. Try running Nurvus again and click 'Open'"
    echo
    echo "METHOD 2 - Right-click Override:"
    echo "1. Control+click (right-click) the nurvus binary"
    echo "2. Select 'Open' from the menu"
    echo "3. Click 'Open' in the warning dialog"
    echo
    echo "METHOD 3 - Manual Terminal Commands:"
    echo "    xattr -c ./$(find_nurvus_binary)"
    echo "    chmod +x ./$(find_nurvus_binary)"
    echo
    log_info "For detailed help, see: https://github.com/bryanveloso/landale/blob/main/docs/MACOS_INSTALLATION.md"
}

# Main setup function
main() {
    echo "=================================================="
    echo "      Nurvus macOS Setup Script"
    echo "=================================================="
    echo
    
    # Check platform
    check_macos
    
    # Find binary
    local binary_file
    binary_file=$(find_nurvus_binary)
    log_success "Found Nurvus binary: $binary_file"
    
    # Setup binary
    remove_quarantine "$binary_file"
    make_executable "$binary_file"
    
    # Test binary
    if test_binary "$binary_file"; then
        log_success "Setup complete! You can now run: ./$binary_file"
        
        # Offer to install to ~/.local/bin
        install_to_local_bin "$binary_file"
        
        echo
        log_success "Nurvus is ready to use!"
        log_info "To start Nurvus, run: ./$binary_file"
        
    else
        log_warning "Automatic setup couldn't bypass macOS security"
        show_manual_instructions
    fi
    
    echo
    echo "=================================================="
    echo "Next steps:"
    echo "1. Run Nurvus: ./$binary_file"
    echo "2. Access web interface: http://localhost:4001"
    echo "3. Configuration file: ~/.config/nurvus/processes.json"
    echo "=================================================="
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Nurvus macOS Setup Script"
        echo
        echo "This script helps set up Nurvus on macOS by:"
        echo "  - Removing quarantine attributes"
        echo "  - Making the binary executable"
        echo "  - Testing if it runs properly"
        echo "  - Optionally installing to ~/.local/bin"
        echo
        echo "Usage:"
        echo "  $0              Run interactive setup"
        echo "  $0 --help      Show this help"
        echo "  $0 --manual    Show manual instructions only"
        echo
        exit 0
        ;;
    --manual)
        show_manual_instructions
        exit 0
        ;;
esac

# Run main setup
main