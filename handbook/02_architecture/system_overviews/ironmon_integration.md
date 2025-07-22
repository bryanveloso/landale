# IronMON Integration Architecture

> How the Pokemon ROM data flows into our streaming system

## The Complete Data Flow

```
Pokemon ROM → Bizhawk Emulator → IronMON Tracker → IronMON Connect Plugin → TCP → Elixir Server → Dashboard/Overlays
```

## Component Breakdown

### IronMON Tracker (Core System)
**Repository**: `besteon/Ironmon-Tracker`  
**Purpose**: Main Lua application running in the emulator

- Reads Pokemon game memory via Bizhawk/mGBA APIs
- Tracks run state: current Pokemon, moves, items, locations, progress
- Displays overlay UI directly in the emulator
- Manages extensions via `CustomCode.ExtensionLibrary`
- Provides event hooks for plugins to access game data

### IronMON Connect (Our Plugin)
**Repository**: `omnypro/ironmon-connect`  
**Purpose**: Bridge between tracker and external systems

- Hooks into the main tracker's event system
- Accesses tracked game data from the core tracker
- Formats data as JSON messages for external consumption
- Sends via TCP using BizHawk's `comm.socketServerSend()`

## Plugin Integration Process

**Configuration**:
```ini
# Settings.ini in IronMON Tracker
[EXTENSIONS]
IronmonConnect=true
```

**Event Flow**:
1. User enables IronMON Connect in tracker settings
2. Tracker loads Connect plugin on startup
3. Plugin hooks into tracker events (checkpoint cleared, location changed, etc.)
4. Plugin formats and sends TCP messages to our Elixir server
5. Elixir server distributes events to dashboard/overlays

## Data Source Hierarchy

1. **Pokemon ROM memory** → Raw game state
2. **IronMON Tracker** → Processed, structured game data
3. **IronMON Connect Plugin** → Filtered events for external systems
4. **TCP Protocol** → Standardized message format
5. **Our Elixir Server** → Event distribution to dashboard/overlays

## What Connect Actually Sends

The plugin has access to full game state but selectively sends:

- **Init**: When tracker starts/resets
- **Seed**: New attempt/run started  
- **Checkpoint**: Major progress milestones (gym leaders, etc.)
- **Location**: Map/area changes

## Why This Architecture Works

**Separation of Concerns**:
- Main tracker = Rich UI and complete game tracking
- Connect plugin = Lightweight external data export
- Tracker focuses on gameplay, plugin on streaming/external tools

**Extensibility**:
- Other plugins could export different data sets
- Our streaming needs don't interfere with core tracker functionality

**Reliability**:
- Plugin failure doesn't break the main tracker
- TCP connection issues don't affect gameplay tracking

## Our Integration Points

**TCP Server**: `apps/server/lib/server/services/ironmon_tcp.ex`
- Receives JSON messages from Connect plugin
- Parses and validates incoming data
- Forwards to Phoenix channels for real-time updates

**Data Models**: `apps/server/lib/server/ironmon/`
- Challenge, Checkpoint, Result, Seed structs
- Database persistence for historical tracking
- Pattern matching for different message types

**Channel Broadcasting**: `overlay:ironmon`, `dashboard:main`
- Real-time updates to streaming overlays
- Dashboard display of current run status
- Historical analysis and pattern recognition

## Configuration Notes

**Plugin Setup**:
- Must be enabled in IronMON Tracker settings
- TCP port configured to match our server (8080)
- JSON message format is standardized by the plugin

**Our Server Setup**:
- TCP listener on port 8080
- JSON parsing with error handling
- Database persistence for run history

## Development Workflow

When working with IronMON integration:

1. **Start IronMON Tracker** with Connect plugin enabled
2. **Start our TCP server** (`apps/server`)
3. **Monitor Phoenix channels** for real-time updates
4. **Check database** for historical run data

**Debug Commands**:
```bash
# Check TCP connection
lsof -i :8080

# Monitor Phoenix channels
wscat -c ws://localhost:7175/socket
```

## Why This Matters

This architecture explains why our TCP server implementation works correctly - we're receiving standardized output from the IronMON Connect plugin, which itself is consuming rich game data from the main IronMON Tracker. The tracker does the heavy lifting of game state analysis, while Connect provides the clean external interface we need for streaming.

---

*This integration is foundational for IronMON streaming content. The plugin architecture keeps our concerns separate while providing the data we need for overlays and analysis.*