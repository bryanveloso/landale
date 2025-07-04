# Nurvus

A lightweight, distributed process manager built with Elixir OTP that provides PM2-like functionality with proper supervision, health monitoring, and real-time metrics across multiple machines.

## Features

- **Distributed Process Management** - Manage processes across multiple machines (Zelan, Demi, Saya, Alys)
- **Platform Detection** - Cross-platform support for Windows, macOS, and Linux
- **Process Lifecycle Management** - Start, stop, restart external processes
- **Health Monitoring** - Real-time CPU, memory, and performance metrics
- **Auto-restart** - Configurable automatic restart on process failure
- **Configuration-based** - Machine-specific JSON configurations with validation
- **HTTP API** - RESTful endpoints for dashboard integration and cross-machine monitoring
- **OTP Supervision** - Proper fault tolerance with Elixir supervision trees

## Quick Start

### Installation

Start the Nurvus application:

```bash
mix deps.get
iex -S mix
```

The HTTP API will be available at `http://localhost:4001`

### Configuration

Nurvus supports machine-specific configurations. Create configuration files for each machine:

**Zelan (Mac Studio - AI Services):**
```bash
# Load Zelan configuration
curl -X POST http://localhost:4001/api/config/load \
  -H "Content-Type: application/json" \
  -d '{"machine": "zelan"}'
```

**Demi (Windows - Streaming):**
```bash
# Load Demi configuration  
curl -X POST http://localhost:4001/api/config/load \
  -H "Content-Type: application/json" \
  -d '{"machine": "demi"}'
```

**Example configuration (`config/zelan.json`):**
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
- [Configuration Guide](config/processes.sample.json) - Sample process configuration

## Distributed Architecture

Nurvus manages processes across multiple machines in the Landale streaming infrastructure:

### Machine Roles

- **Zelan (Mac Studio)** - AI services (Phononmaser, Analysis, LM Studio)
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

```bash
# Format code
mix format

# Run code analysis
mix credo --strict

# Start in development
iex -S mix
```
