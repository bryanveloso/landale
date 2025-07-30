# Nurvus

A lightweight, distributed process manager built with Elixir OTP that provides PM2-like functionality as single executables across multiple machines.

## Features

- **Single Executable** - No dependencies, just download and run
- **Distributed Process Management** - Manage processes across multiple machines
- **Platform Detection** - Cross-platform support for Windows, macOS, and Linux
- **Process Lifecycle Management** - Start, stop, restart external processes
- **Health Monitoring** - Real-time CPU, memory, and performance metrics
- **Auto-restart** - Configurable automatic restart on process failure
- **Configuration-based** - Machine-specific JSON configurations
- **HTTP API** - RESTful endpoints for dashboard integration
- **OTP Supervision** - Proper fault tolerance with Elixir supervision trees

## Quick Start

### Installation

1. **Download** the appropriate package for your machine from [GitHub Releases](https://github.com/bryanveloso/landale/releases/tag/nurvus-latest)
2. **Extract**: `tar -xzf nurvus-[machine].tar.gz`
3. **Run**: `./nurvus` (or `nurvus.exe` on Windows)

The HTTP API will be available at `http://localhost:4001`

#### macOS Installation

On macOS, you may see security warnings when running Nurvus since it's an unsigned binary. To bypass these:

**Quick Fix (Terminal):**

```bash
# Remove quarantine attributes
xattr -c nurvus_macos

# Make executable and run
chmod +x nurvus_macos
./nurvus_macos
```

**GUI Method:**

1. Try to run Nurvus (you'll see a security warning)
2. Open **System Settings** → **Privacy & Security**
3. Scroll to **Security** section
4. Click **"Allow Anyway"** next to the Nurvus warning
5. Try running Nurvus again and click **"Open"**

For detailed macOS installation instructions, see [macOS Installation Guide](../../docs/MACOS_INSTALLATION.md).

### Configuration

Each package includes machine-specific configuration that's automatically copied to `~/.nurvus/processes.json` on first run.

**Example configuration:**

```json
[
  {
    "id": "phononmaser",
    "name": "Phononmaser Audio Service",
    "command": "bun",
    "args": ["--hot", "./index.ts"],
    "cwd": "/opt/landale/apps/phononmaser",
    "platform": "darwin",
    "auto_restart": true
  }
]
```

### API Usage

```bash
# List processes
curl http://localhost:4001/api/processes

# Start a process
curl -X POST http://localhost:4001/api/processes/my_app/start

# Get process metrics
curl http://localhost:4001/api/processes/my_app/metrics

# System status
curl http://localhost:4001/api/system/status
```

## Documentation

- [API Documentation](API.md) - Complete HTTP API reference
- [Deployment Guide](DEPLOYMENT.md) - Installation and setup instructions
- [Configuration Guide](config/processes.sample.json) - Sample process configuration

## Distributed Architecture

Nurvus manages processes across multiple machines in the Landale streaming infrastructure:

### Machine Roles

- **Zelan (Mac Studio)** - AI services (Phononmaser, SEED, LM Studio)
- **Demi (Windows PC)** - Streaming apps (OBS Studio, VTube Studio, TITS)
- **Saya (Mac Mini)** - Docker services (Landale stack)
- **Alys (Windows VM)** - Automation (Streamer.Bot)

### Components

- **ProcessManager** - Main GenServer managing process configurations
- **ProcessSupervisor** - Dynamic supervisor for external processes
- **ProcessRunner** - GenServer wrapping individual processes
- **ProcessMonitor** - Health monitoring and metrics collection
- **Platform** - Cross-platform process detection (Windows/macOS/Linux)
- **HttpServer** - Plug/Bandit HTTP API server with cross-machine endpoints

### Cross-Machine Monitoring

```bash
# Get platform information
curl http://zelan.local:4001/api/platform

# Check if OBS is running on Demi
curl http://demi.local:4001/api/platform/processes/obs64.exe

# Get detailed health from all machines
curl http://saya.local:4001/api/health/detailed
```

## Environment Variables

- `NURVUS_PORT` - HTTP server port (default: 4001)
- `NURVUS_CONFIG_FILE` - Path to process configuration file

## Development

For development, see the main repository for build instructions using Mix and Elixir.
