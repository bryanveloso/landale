# Nurvus Deployment Guide

Complete deployment guide for Nurvus process manager across your streaming infrastructure.

## Overview

Nurvus is designed to run on each machine in your streaming setup:

- **Zelan (Mac Studio)** - AI services (Phononmaser, Analysis, LM Studio)  
- **Demi (Windows PC)** - Streaming apps (OBS, VTube Studio, TITS)
- **Saya (Mac Mini)** - Docker services (Landale stack)
- **Alys (Windows VM)** - Automation (Streamer.Bot)

## Quick Start

### 1. Prerequisites

**Build Machine Only (typically Zelan):**
- Elixir 1.16+ and Erlang/OTP 26+
- Git access to the repository

**Target Machines (all others):**
- **NO Elixir/Erlang installation required!**
- Mix releases are self-contained with the runtime included

**Build Machine Setup (macOS):**
```bash
brew install elixir
```

**OR for Windows build machine:**
```powershell
choco install elixir
```

### 2. Build Release (Build Machine Only)

```bash
# Clone repository (on build machine)
git clone <repository-url>
cd landale/apps/nurvus

# Build production release
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix release

# Package for distribution
tar -czf nurvus-release.tar.gz -C _build/prod/rel/nurvus .
```

### 3. Deploy to Target Machines

**No Elixir installation needed on target machines!**

Copy the release package and extract:
```bash
# Copy nurvus-release.tar.gz to target machine
# Then extract:
sudo mkdir -p /opt/nurvus
sudo tar -xzf nurvus-release.tar.gz -C /opt/nurvus/
```

### 3. Machine-Specific Configuration

Each machine has its own configuration file:

```bash
# Copy appropriate config for your machine
cp config/zelan.json config/processes.json     # Mac Studio
cp config/demi.json config/processes.json      # Windows PC  
cp config/saya.json config/processes.json      # Mac Mini
cp config/alys.json config/processes.json      # Windows VM
```

### 4. Test Run

```bash
# Test locally first
iex -S mix

# Or run in background
mix run --no-halt
```

### 5. Deploy to Production

Choose your deployment method:

## Deployment Methods

### Option A: Mix Releases (Recommended)

Mix releases create self-contained deployments with the Erlang runtime.

#### Build Release

```bash
# Configure for production
export MIX_ENV=prod

# Build release
mix release

# Release will be in _build/prod/rel/nurvus/
```

#### Deploy Release

```bash
# Copy to target location
sudo mkdir -p /opt/nurvus
sudo cp -r _build/prod/rel/nurvus/* /opt/nurvus/

# Set ownership (Unix only)
sudo chown -R $USER:$USER /opt/nurvus
```

#### Run Release

```bash
# Start
/opt/nurvus/bin/nurvus start

# Stop  
/opt/nurvus/bin/nurvus stop

# Check status
/opt/nurvus/bin/nurvus pid
```

### Option B: Direct Execution

Run directly from source code (development/testing).

```bash
# Development
iex -S mix

# Production mode
MIX_ENV=prod mix run --no-halt

# Background daemon
nohup mix run --no-halt > nurvus.log 2>&1 &
```

### Option C: Systemd Services (Linux/macOS)

#### Create Service File

**macOS (Zelan, Saya)** - `/usr/local/etc/systemd/system/nurvus.service`:
```ini
[Unit]
Description=Nurvus Process Manager
After=network.target

[Service]
Type=exec
User=bryan
WorkingDirectory=/opt/landale/apps/nurvus
ExecStart=/opt/nurvus/bin/nurvus start
ExecStop=/opt/nurvus/bin/nurvus stop
Restart=always
RestartSec=5
Environment=MIX_ENV=prod
Environment=NURVUS_PORT=4001

[Install]
WantedBy=multi-user.target
```

#### Enable Service

```bash
# Enable and start
sudo systemctl enable nurvus
sudo systemctl start nurvus

# Check status
sudo systemctl status nurvus

# View logs
sudo journalctl -u nurvus -f
```

### Option D: Windows Services (Demi, Alys)

#### Using NSSM (Non-Sucking Service Manager)

```powershell
# Install NSSM
choco install nssm

# Create service
nssm install Nurvus "C:\elixir\bin\mix.bat"
nssm set Nurvus Parameters "run --no-halt"
nssm set Nurvus AppDirectory "C:\landale\apps\nurvus"
nssm set Nurvus DisplayName "Nurvus Process Manager"
nssm set Nurvus Description "PM2-like process manager for streaming setup"

# Set environment
nssm set Nurvus AppEnvironmentExtra MIX_ENV=prod NURVUS_PORT=4001

# Start service
nssm start Nurvus
```

#### Check Windows Service

```powershell
# Service status
sc query Nurvus

# Start/stop
net start Nurvus
net stop Nurvus

# View logs (check Windows Event Viewer)
```

## Machine-Specific Deployment

### Zelan (Mac Studio) - AI Services

```bash
# Dependencies for AI services
brew install python@3.11 ffmpeg

# Nurvus configuration
cp config/zelan.json config/processes.json

# Deploy using systemd
sudo cp deployment/zelan/nurvus.service /usr/local/etc/systemd/system/
sudo systemctl enable nurvus
sudo systemctl start nurvus

# Verify services
curl http://zelan.local:4001/api/platform
curl http://zelan.local:4001/api/processes
```

**Managed Processes:**
- Phononmaser (Python audio service)
- Analysis (Python ML service) 
- LM Studio (Local language model server)

### Demi (Windows PC) - Streaming

```powershell
# Nurvus configuration  
Copy-Item config\demi.json config\processes.json

# Deploy as Windows service
nssm install Nurvus "C:\elixir\bin\mix.bat"
nssm set Nurvus Parameters "run --no-halt"
nssm set Nurvus AppDirectory "C:\landale\apps\nurvus"
nssm start Nurvus

# Verify streaming apps
curl http://demi.local:4001/api/platform/processes/obs64.exe
curl http://demi.local:4001/api/processes
```

**Managed Processes:**
- OBS Studio (Streaming software)
- VTube Studio (Avatar software)
- TITS Launcher (Text-to-speech)

### Saya (Mac Mini) - Docker

```bash
# Docker must be running
docker --version

# Nurvus configuration
cp config/saya.json config/processes.json

# Deploy
sudo systemctl enable nurvus
sudo systemctl start nurvus

# Verify Docker services
curl http://saya.local:4001/api/processes/landale-stack
curl http://saya.local:4001/api/health/detailed
```

**Managed Processes:**
- Landale Docker Stack (Main application)

### Alys (Windows VM) - Automation

```powershell
# Nurvus configuration
Copy-Item config\alys.json config\processes.json

# Deploy as service
nssm install Nurvus "C:\elixir\bin\mix.bat"
nssm start Nurvus

# Verify automation
curl http://alys.local:4001/api/platform/processes/Streamer.Bot.exe
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
3. `config/processes.json` (default)

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
