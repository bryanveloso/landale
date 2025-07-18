# Nurvus Deployment Guide

Complete deployment guide for Nurvus single-executable process manager.

## Overview

Nurvus is deployed as single executables to each machine in your streaming setup:

- **Zelan (Mac Studio)** - AI services (Phononmaser, Analysis, LM Studio)  
- **Demi (Windows PC)** - Streaming apps (OBS, VTube Studio, TITS)
- **Saya (Mac Mini)** - Docker services (Landale stack)
- **Alys (Windows VM)** - Automation (Streamer.Bot)

## Quick Start

### 1. Download Machine Package

Download the appropriate package for your machine from GitHub Actions artifacts:

- `nurvus-zelan.tar.gz` - Mac Studio
- `nurvus-saya.tar.gz` - Mac Mini  
- `nurvus-demi.tar.gz` - Windows PC
- `nurvus-alys.tar.gz` - Windows VM

### 2. Extract and Run

```bash
# Extract package
tar -xzf nurvus-[machine].tar.gz

# Run directly (config will be copied to ~/.config/nurvus/ on first run)
./nurvus  # or nurvus.exe on Windows
```

#### macOS Security Setup

On macOS machines (Zelan, Saya), you'll need to bypass Gatekeeper since Nurvus is unsigned:

```bash
# Remove quarantine attributes (required on macOS)
xattr -c nurvus_macos

# Make executable
chmod +x nurvus_macos

# Run
./nurvus_macos
```

**Alternative (GUI method):**
1. Try to run Nurvus (you'll see a security warning)
2. Go to **System Settings** → **Privacy & Security** 
3. Click **"Allow Anyway"** in the Security section
4. Try running again and click **"Open"**

For detailed troubleshooting, see [macOS Installation Guide](../../docs/MACOS_INSTALLATION.md).

That's it! No dependencies, no build process, no configuration copying.

## Auto-Start Setup

### macOS/Linux: Systemd Service

Each package includes a `nurvus.service` file for auto-startup:

```bash
# Install the service
sudo cp nurvus.service /etc/systemd/system/nurvus-[machine].service

# Enable auto-start on boot
sudo systemctl daemon-reload
sudo systemctl enable nurvus-[machine]

# Start now
sudo systemctl start nurvus-[machine]

# Check status
sudo systemctl status nurvus-[machine]
```

### Windows: Manual Service Setup

For Windows machines (Demi/Alys), use NSSM:

```powershell
# Install NSSM
choco install nssm

# Create service (from nurvus directory)
nssm install Nurvus "C:\path\to\nurvus.exe"
nssm set Nurvus DisplayName "Nurvus Process Manager"
nssm set Nurvus Description "PM2-like process manager for streaming setup"

# Start service
nssm start Nurvus

# Check status
sc query Nurvus
```

## Machine-Specific Details

### Zelan (Mac Studio) - AI Services

```bash
# Download and extract
tar -xzf nurvus-zelan.tar.gz

# Run (config auto-copied to ~/.nurvus/)
./nurvus

# Install systemd service
sudo cp nurvus.service /etc/systemd/system/nurvus-zelan.service
sudo systemctl enable nurvus-zelan
sudo systemctl start nurvus-zelan

# Verify
curl http://zelan.local:4001/health
```

**Managed Processes:**
- Phononmaser (Python audio service)
- Analysis (Python ML service) 
- LM Studio (Local language model server)

### Saya (Mac Mini) - Docker Services

```bash
# Download and extract
tar -xzf nurvus-saya.tar.gz

# Run
./nurvus

# Install systemd service
sudo cp nurvus.service /etc/systemd/system/nurvus-saya.service
sudo systemctl enable nurvus-saya
sudo systemctl start nurvus-saya

# Verify
curl http://saya.local:4001/health
```

**Managed Processes:**
- Landale Docker Stack (Main application)

### Demi (Windows PC) - Streaming

```powershell
# Extract package
tar -xzf nurvus-demi.tar.gz

# Run
.\nurvus.exe

# Install as service
nssm install Nurvus "C:\path\to\nurvus.exe"
nssm start Nurvus

# Verify
curl http://demi.local:4001/health
```

**Managed Processes:**
- OBS Studio (Streaming software)
- VTube Studio (Avatar software)
- TITS Launcher (Text-to-speech)

### Alys (Windows VM) - Automation

```powershell
# Extract package
tar -xzf nurvus-alys.tar.gz

# Run
.\nurvus.exe

# Install as service
nssm install Nurvus "C:\path\to\nurvus.exe"
nssm start Nurvus

# Verify
curl http://alys.local:4001/health
```

**Managed Processes:**
- Streamer.Bot (Stream automation)

## Configuration

### Environment Variables

```bash
# HTTP server port (default: 4001)
export NURVUS_PORT=4001

# Config file location
export NURVUS_CONFIG_FILE="/path/to/config.json"

# Production environment
export MIX_ENV=prod
```

### Config File Locations

**Default locations by priority:**
1. `NURVUS_CONFIG_FILE` environment variable
2. Application config `:nurvus, :config_file`
3. `~/.nurvus/processes.json` (default)

**Auto-initialization:**
- On first run, if `~/.nurvus/` doesn't exist, Nurvus will copy `./processes.json` to `~/.nurvus/processes.json`

### Network Configuration

Nurvus runs on port 4001 by default. Ensure this port is accessible between machines:

```bash
# Test connectivity
curl http://machine.local:4001/health

# macOS firewall
sudo pfctl -f /etc/pf.conf

# Windows firewall
New-NetFirewallRule -DisplayName "Nurvus" -Direction Inbound -Port 4001 -Protocol TCP -Action Allow
```

## Monitoring & Observability

### Health Checks

```bash
# Basic health
curl http://localhost:4001/health

# Detailed status  
curl http://localhost:4001/api/health/detailed

# Platform info
curl http://localhost:4001/api/platform
```

### Telemetry Integration

Enable telemetry handlers for monitoring:

```elixir
# In your monitoring system
Nurvus.TelemetryExample.attach_handlers()

# Available events:
# - [:nurvus, :process, :started|:stopped|:crashed]
# - [:nurvus, :http, :request] 
# - [:nurvus, :metrics, :collected]
# - [:nurvus, :alert, :generated]
```

### Log Locations

**Development:**
- Console output

**Systemd:**
```bash
sudo journalctl -u nurvus -f
```

**Windows Service:**
- Windows Event Viewer → Applications
- Or redirect to file with NSSM

## Troubleshooting

### Common Issues

**Port already in use:**
```bash
# Find process using port 4001
lsof -i :4001              # macOS/Linux
netstat -ano | findstr 4001  # Windows

# Change port
export NURVUS_PORT=4002
```

**Permission denied:**
```bash
# Fix ownership (Unix)
sudo chown -R $USER:$USER /opt/nurvus

# Windows: Run as Administrator
```

**Process won't start:**
```bash
# Check logs for errors
tail -f nurvus.log

# Verify config syntax
mix run -e "Nurvus.Config.load_config() |> IO.inspect"

# Test individual commands
bun --version  # For Bun processes
python --version  # For Python processes
```

**Network connectivity:**
```bash
# Test from another machine
curl -v http://machine.local:4001/health

# Check firewall rules
sudo iptables -L  # Linux
pfctl -sr  # macOS
```

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=debug
mix run --no-halt

# Or in release
NURVUS_LOG_LEVEL=debug /opt/nurvus/bin/nurvus start
```

### Cross-Machine Testing

```bash
# Test from dashboard machine
for machine in zelan demi saya alys; do
  echo "Testing $machine..."
  curl -s http://$machine.local:4001/api/platform | jq .platform
done
```

## Updates & Maintenance

### Update Deployment

```bash
# Pull latest code
git pull origin main

# Rebuild
mix deps.get
mix compile

# Restart service
sudo systemctl restart nurvus  # Unix
nssm restart Nurvus  # Windows
```

### Backup Configuration

```bash
# Backup configs
cp config/processes.json config/processes.json.backup

# Version control
git add config/
git commit -m "Update process configurations"
```

### Performance Tuning

```bash
# Increase Erlang VM memory (if needed)
export ERL_MAX_PORTS=32768
export ERL_MAX_ETS_TABLES=32768

# For releases, edit vm.args file
echo "+P 1048576" >> /opt/nurvus/releases/0.1.0/vm.args
```

## Security Considerations

- Nurvus runs on local network only
- No authentication required (trusted environment)
- Process commands defined in config files (not user input)
- Each machine manages its own processes only

## Support

For issues or questions:
1. Check logs first
2. Verify network connectivity
3. Test individual process commands manually
4. Check this documentation
5. File issue in repository
