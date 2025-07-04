# Landale System Architecture

## Two Separate Systems

This project consists of **TWO COMPLETELY SEPARATE SYSTEMS** that serve different purposes:

### 1. THE SERVER (Current Priority)
**Purpose:** Replace the legacy server application with full streaming functionality.

**Responsibilities:**
- OBS WebSocket connections and control
- Twitch EventSub API integration  
- IronMON TCP server (port 8080)
- Dashboard API endpoints
- All streaming application functionality
- Phoenix web interface
- Real-time WebSocket communication

**Location:** `/apps/server/`

**Status:** Currently being developed to replace the old server

---

### 2. PROCESS MONITOR (Separate Project - Future)
**Purpose:** Replace PM2 with distributed OS process monitoring across machines.

**Responsibilities:**
- Check if OS processes are running (`tasklist`/`ps` commands)
- Start/stop OS processes (`System.cmd`)
- Monitor processes like `obs64.exe`, `VTubeStudio.exe`
- Report process status to dashboard
- Enable remote process control ("Restart OBS on demi" button)

**What it does NOT include:**
- NO EventSub integration
- NO WebSocket connections to applications
- NO TCP servers
- NO application-specific APIs
- NO dependencies on server features

**Status:** Separate project, lower priority, will be created after server is complete

---

## Why They Cannot Be Combined

**Dependency Pollution:** A minimal process monitor should not include Twitch API libraries, OBS WebSocket clients, or TCP servers. Combining them means even a simple "check if OBS is running" requires compiling all the server dependencies.

**Clean Separation:** Each system has a distinct purpose and should remain focused on its core responsibility.

## Current Focus

**PRIORITY 1:** Complete the server replacement  
**PRIORITY 2:** Process monitor (separate Elixir application)

## Managed Processes Per Machine

### Zelan (Mac Studio) - AI Services
- **phononmaser**: Audio processing service (Python, port 8889)
  - Script: `/Users/Avalonstar/Code/bryanveloso/landale/apps/phononmaser/.venv/bin/python -m src.main`
  - Working directory: `/Users/Avalonstar/Code/bryanveloso/landale/apps/phononmaser`
  - Health port: 8890
- **seed**: SEED Intelligence service (Python)
  - Script: `/Users/Avalonstar/Code/bryanveloso/landale/apps/seed/.venv/bin/python -m src.main`
  - Working directory: `/Users/Avalonstar/Code/bryanveloso/landale/apps/seed`
- **lms**: LM Studio Server (command-line, port 1234)
  - Command: `lms server start --port 1234`

### Demi (Windows) - Streaming Applications
- **obs-studio**: OBS Studio (`obs64.exe`)
  - Path: `"C:\Program Files\obs-studio\bin\64bit\obs64.exe" --enable-media-stream`
  - Working directory: `C:\Program Files\obs-studio\bin\64bit`
- **vtube-studio**: VTube Studio (`VTube Studio.exe`)
  - Path: `"D:\Steam\steamapps\common\VTube Studio\VTube Studio.exe"`
  - Working directory: `D:\Steam\steamapps\common\VTube Studio`
- **tits**: TITS Launcher (`TITS Launcher.exe`)
  - Path: `"D:\Applications\TITS\TITS Launcher.exe"`
  - Working directory: `D:\Applications\TITS`

### Saya (Mac Mini) - Docker Services
- **stack**: Entire Landale Docker stack
  - Compose file: `/opt/landale/docker-compose.yml`
  - Working directory: `/opt/landale`
  - Containers: landale-server, landale-overlays, postgres, seq

### Alys (Windows Gaming PC) - Streaming Automation
- **streamer-bot**: Streamer.Bot (`Streamer.Bot.exe`)
  - Path: `"D:\Utilities\Streamer.Bot\Streamer.Bot.exe"`
  - Working directory: `D:\Utilities\Streamer.Bot`

## Architecture Decision

The server handles all streaming application logic.  
The process monitor handles OS-level process management.  
They communicate through simple APIs, not shared code.