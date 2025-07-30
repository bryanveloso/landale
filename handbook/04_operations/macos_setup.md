# macOS Setup Guide

> Getting Nurvus running on macOS with Gatekeeper security

## Quick Start

```bash
cd ~/Downloads
xattr -c nurvus_macos
chmod +x nurvus_macos
./nurvus_macos
```

## The Gatekeeper Problem

macOS blocks unsigned binaries by default with warnings like:

- `"nurvus" is damaged and can't be opened`
- `"nurvus" cannot be opened because it is from an unidentified developer`
- `macOS cannot verify that this app is free from malware`

These warnings appear because Nurvus isn't code-signed with an Apple Developer certificate, not because it's actually malicious.

## Installation Methods

### Method 1: Terminal (Recommended)

The fastest approach:

1. Download Nurvus from GitHub releases
2. Open Terminal
3. Navigate to downloads: `cd ~/Downloads`
4. Remove quarantine: `xattr -c nurvus_macos`
5. Make executable: `chmod +x nurvus_macos`
6. Run: `./nurvus_macos`

### Method 2: System Settings (GUI)

**macOS Ventura (13.0+)**:

1. Double-click Nurvus binary → see error
2. Open System Settings → Privacy & Security
3. Scroll to Security section
4. Find Nurvus blocked message → Click "Allow Anyway"
5. Try running again → Click "Open" when prompted

**macOS Big Sur/Monterey**:

1. Double-click Nurvus binary → see error
2. Open System Preferences → Security & Privacy
3. Unlock with password
4. Find Nurvus blocked message → Click "Allow Anyway"
5. Try running again

### Method 3: Right-Click Override

Quick one-time bypass:

1. Control+click (or right-click) the Nurvus binary
2. Select "Open" from context menu
3. Click "Open" in warning dialog

## System-Wide Installation

Install to `~/.local/bin` for command-line access:

```bash
# Create directory
mkdir -p ~/.local/bin

# Copy and prepare binary
cp nurvus_macos ~/.local/bin/nurvus
xattr -c ~/.local/bin/nurvus
chmod +x ~/.local/bin/nurvus

# Add to PATH (add to ~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"

# Reload shell and test
source ~/.zshrc
nurvus --help
```

## Troubleshooting

### Permission Errors

```bash
sudo xattr -c /path/to/nurvus_macos
sudo chmod +x /path/to/nurvus_macos
```

### Bad CPU Type Error

- Download the **macOS** version
- Nurvus only supports **Apple Silicon** (M1/M2/M3)
- Intel Macs are not supported

### Persistent "Damaged" Messages

```bash
sudo xattr -rds com.apple.quarantine /path/to/nurvus_macos
```

### Verification Commands

```bash
# Check permissions
ls -la nurvus_macos

# Verify quarantine removal (should show no output)
xattr -l nurvus_macos
```

## Security Context

**Why this is safe for Nurvus**:

- Open source code (reviewable)
- Built from public CI/CD
- No network access required
- Single-purpose process management tool

**Best practices**:

- Download only from official GitHub releases
- Verify checksums if provided: `shasum -a 256 nurvus_macos`
- Don't bypass Gatekeeper for unknown software

## Alternative: Build from Source

If you prefer compiling yourself:

```bash
git clone https://github.com/bryanveloso/landale
cd landale/apps/nurvus
mix deps.get
MIX_ENV=prod mix release
```

---

_One-time setup enables Nurvus to run normally in future launches_
