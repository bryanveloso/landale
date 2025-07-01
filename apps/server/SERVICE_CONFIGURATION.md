# Service Configuration Guide

This guide explains how to configure and control services across your distributed Elixir cluster.

## Overview

The cluster supports managing different types of services across 4 machines:

- **zelan** (Mac Studio) - Controller node with API + AI services (phononmaser, analysis, lms)
- **demi** (Windows) - Streaming applications (OBS, VTube Studio, TITS)
- **saya** (Mac Mini) - Docker Compose services (server, overlays, postgres)
- **alys** (Windows) - Gaming applications (Streamer.Bot)

## Platform-Specific Service Configuration

### Windows Services (demi)

**File**: `lib/server/process_supervisor/demi.ex`

Currently configured Windows applications (demi):
```elixir
@managed_processes %{
  "obs-studio" => %{
    name: "obs-studio",
    display_name: "OBS Studio",
    executable: "obs64.exe",
    start_command: ~s["C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe" --enable-media-stream],
    process_name: "obs64.exe"
  },
  "vtube-studio" => %{
    name: "vtube-studio",
    display_name: "VTube Studio",
    executable: "VTube Studio.exe",
    start_command: ~s["D:\\Steam\\steamapps\\common\\VTube Studio\\VTube Studio.exe"],
    process_name: "VTube Studio.exe"
  },
  "tits" => %{
    name: "tits",
    display_name: "TITS Launcher",
    executable: "TITS Launcher.exe",
    start_command: ~s["D:\\Applications\\TITS\\TITS Launcher.exe"],
    process_name: "TITS Launcher.exe"
  }
}
```

**To add a new Windows application**:
1. Find the executable path and process name
2. Add to the `@managed_processes` map
3. Rebuild and redeploy

### Docker Services (saya)

**File**: `lib/server/process_supervisor/saya.ex`

**Note**: Saya runs Docker containers via OrbStack, which provides excellent container management. This supervisor is kept minimal and only manages the entire stack as one unit.

Currently configured (saya):
```elixir
@managed_processes %{
  "stack" => %{
    name: "stack",
    display_name: "Landale Docker Stack",
    type: :docker_compose_stack,
    description: "Entire Landale stack (server, overlays, postgres, seq)"
  }
}
```

**Individual container management**: Use OrbStack UI - it's much better than what we could build here!

### Windows Gaming Services (alys)

**File**: `lib/server/process_supervisor/alys.ex`

Currently configured Windows applications (alys):
```elixir
@managed_processes %{
  "streamer-bot" => %{
    name: "streamer-bot",
    display_name: "Streamer.Bot",
    executable: "Streamer.Bot.exe",
    start_command: ~s["D:\\Utilities\\Streamer.Bot\\Streamer.Bot.exe"],
    process_name: "Streamer.Bot.exe"
  }
}
```

### macOS AI Services (zelan)

**File**: `lib/server/process_supervisor/zelan.ex`

Currently configured macOS services:
```elixir
@managed_processes %{
  "phononmaser" => %{
    name: "phononmaser",
    display_name: "Phononmaser Audio Processing",
    type: :python_service,
    script_path: "/Users/Avalonstar/Code/bryanveloso/landale/apps/phononmaser/.venv/bin/python",
    args: ["-m", "src.main"]
  },
  "analysis" => %{
    name: "analysis",
    display_name: "Analysis Service", 
    type: :python_service,
    script_path: "/Users/Avalonstar/Code/bryanveloso/landale/apps/analysis/.venv/bin/python",
    args: ["-m", "src.main"]
  },
  "lms" => %{
    name: "lms",
    display_name: "LM Studio Server",
    type: :command_service,
    command: "lms",
    args: ["server", "start", "--port", "1234"]
  }
}
```

## Adding New Services

### Step 1: Choose Your Machine

Decide which machine should manage the service:
- **demi**: Windows applications that need GUI access
- **saya/alys**: Linux system services
- **zelan**: macOS applications (controller already runs here)

### Step 2: Add Service Configuration

Edit the appropriate platform supervisor file and add your service to `@managed_processes`.

**Windows Example** (adding VLC):
```elixir
"vlc" => %{
  name: "vlc",
  display_name: "VLC Media Player",
  executable: "vlc.exe", 
  start_command: ~s["C:\\Program Files\\VideoLAN\\VLC\\vlc.exe"],
  process_name: "vlc.exe"
}
```

**Linux Example** (adding Apache):
```elixir
"apache" => %{
  name: "apache",
  display_name: "Apache Web Server",
  service_name: "apache2",
  process_name: "apache2",
  type: :systemd_service
}
```

**macOS Example** (adding VS Code):
```elixir
"vscode" => %{
  name: "vscode",
  display_name: "Visual Studio Code",
  app_name: "Visual Studio Code",
  bundle_id: "com.microsoft.VSCode", 
  app_path: "/Applications/Visual Studio Code.app"
}
```

### Step 3: Rebuild and Deploy

1. Build new releases: `./deploy/build_releases.sh`
2. Deploy to target machines using deployment scripts
3. Test the new service configuration

## Using the API

### Authentication

All API calls require authentication via X-API-Key header:
```bash
export API_KEY="your_secure_api_key_here"
curl -H "X-API-Key: $API_KEY" http://zelan.local:4000/api/processes/cluster
```

### Available Endpoints

**Get cluster status**:
```bash
GET /api/processes/cluster
```

**List processes on a node**:
```bash
GET /api/processes/{node}
# Example: GET /api/processes/demi
```

**Get specific process status**:
```bash
GET /api/processes/{node}/{process}
# Example: GET /api/processes/demi/obs-studio
```

**Start a process**:
```bash
POST /api/processes/{node}/{process}/start
# Example: POST /api/processes/demi/obs-studio/start
```

**Stop a process**:
```bash
POST /api/processes/{node}/{process}/stop
# Example: POST /api/processes/demi/obs-studio/stop
```

**Restart a process**:
```bash
POST /api/processes/{node}/{process}/restart
# Example: POST /api/processes/saya/landale-server/restart
```

## Example Use Cases

### Streaming Setup
```bash
# Start OBS on Windows streaming machine
curl -X POST -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/demi/obs-studio/start

# Start VTube Studio for avatar
curl -X POST -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/demi/vtube-studio/start

# Start Streamer.Bot on gaming machine
curl -X POST -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/alys/streamer-bot/start

# Check if Docker stack is running
curl -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/saya/stack
```

### AI Services Setup
```bash
# Start audio processing on zelan
curl -X POST -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/zelan/phononmaser/start

# Start LM Studio for AI
curl -X POST -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/zelan/lms/start

# Start analysis service
curl -X POST -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/zelan/analysis/start

# Check Docker stack status  
curl -H "X-API-Key: $API_KEY" \\
  http://zelan.local:4000/api/processes/saya/stack
```

## Security Notes

1. **API Key**: Always set a strong API key via environment variable
2. **Network Binding**: Configure `BIND_IP` to your Tailscale IP for production
3. **Process Validation**: Only predefined processes can be controlled
4. **Input Sanitization**: All process names are validated before execution

## Troubleshooting

### Process Not Found
If you get "process_not_managed" error:
1. Check the process name is exactly as defined in `@managed_processes`
2. Verify you're targeting the correct node
3. Ensure the process configuration exists

### Authentication Errors
If you get "Unauthorized" responses:
1. Check your API key is set correctly
2. Verify the X-API-Key header is included
3. Ensure API_KEY environment variable is set on the controller

### Service Won't Start
If a service fails to start:
1. Check the executable path is correct
2. Verify the service exists on the target machine
3. Check node logs for detailed error messages