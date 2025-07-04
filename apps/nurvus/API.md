# Nurvus Process Manager API Documentation

Nurvus is a lightweight process manager built with Elixir OTP that provides PM2-like functionality with proper supervision and real-time monitoring.

## Base URL

```
http://localhost:4001
```

## Authentication

Currently, no authentication is required. This is designed for local development and deployment environments.

## Content Types

All API endpoints accept and return JSON. Include the following header in requests:

```
Content-Type: application/json
```

## Error Handling

All endpoints return consistent error responses in JSON format:

```json
{
  "error": "Error description"
}
```

HTTP status codes used:
- `200` - Success
- `201` - Created
- `400` - Bad Request (validation errors)
- `404` - Not Found
- `500` - Internal Server Error

---

## Health & Status Endpoints

### GET /health

Health check endpoint for service monitoring.

**Response:**
```json
{
  "status": "ok",
  "service": "nurvus",
  "version": "0.1.0",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status:** `200 OK`

### GET /api/system/status

Get overall system status including process counts and health metrics.

**Response:**
```json
{
  "total_processes": 3,
  "running": 2,
  "stopped": 1,
  "failed": 0,
  "alerts": 1,
  "uptime": 3600
}
```

**Status:** `200 OK`

---

## Process Management Endpoints

### GET /api/processes

List all configured processes with their current status.

**Response:**
```json
{
  "processes": [
    {
      "id": "my_app",
      "name": "My Application",
      "status": "running"
    },
    {
      "id": "worker",
      "name": "Background Worker", 
      "status": "stopped"
    }
  ]
}
```

**Status:** `200 OK`

### GET /api/processes/:id

Get detailed information about a specific process.

**Parameters:**
- `id` (string, required) - Process identifier

**Response:**
```json
{
  "id": "my_app",
  "status": "running",
  "metrics": {
    "current": {
      "timestamp": "2024-01-15T10:30:00Z",
      "cpu_percent": 5.2,
      "memory_mb": 128.5,
      "uptime_seconds": 3600,
      "file_descriptors": 15,
      "status": "healthy"
    },
    "history": [...]
  }
}
```

**Status:** `200 OK` | `404 Not Found`

### POST /api/processes

Add a new process configuration.

**Request Body:**
```json
{
  "id": "my_app",
  "name": "My Application",
  "command": "bun",
  "args": ["run", "start"],
  "cwd": "/path/to/app",
  "env": {
    "NODE_ENV": "production",
    "PORT": "3000"
  },
  "auto_restart": true,
  "max_restarts": 3,
  "restart_window": 60
}
```

**Required Fields:**
- `id` (string) - Unique process identifier
- `name` (string) - Human-readable process name  
- `command` (string) - Executable command

**Optional Fields:**
- `args` (array) - Command arguments (default: `[]`)
- `cwd` (string) - Working directory (default: `null`)
- `env` (object) - Environment variables (default: `{}`)
- `auto_restart` (boolean) - Enable automatic restart (default: `false`)
- `max_restarts` (integer) - Maximum restart attempts (default: `3`)
- `restart_window` (integer) - Restart window in seconds (default: `60`)

**Response:**
```json
{
  "status": "created",
  "process_id": "my_app"
}
```

**Status:** `201 Created` | `400 Bad Request`

### DELETE /api/processes/:id

Remove a process configuration and stop it if running.

**Parameters:**
- `id` (string, required) - Process identifier

**Response:**
```json
{
  "status": "removed",
  "process_id": "my_app"
}
```

**Status:** `200 OK` | `404 Not Found`

---

## Process Control Endpoints

### POST /api/processes/:id/start

Start a configured process.

**Parameters:**
- `id` (string, required) - Process identifier

**Response:**
```json
{
  "status": "started",
  "process_id": "my_app"
}
```

**Status:** `200 OK` | `404 Not Found` | `500 Internal Server Error`

### POST /api/processes/:id/stop

Stop a running process.

**Parameters:**
- `id` (string, required) - Process identifier

**Response:**
```json
{
  "status": "stopped", 
  "process_id": "my_app"
}
```

**Status:** `200 OK` | `404 Not Found` | `500 Internal Server Error`

### POST /api/processes/:id/restart

Restart a process (stop then start).

**Parameters:**
- `id` (string, required) - Process identifier

**Response:**
```json
{
  "status": "restarted",
  "process_id": "my_app"
}
```

**Status:** `200 OK` | `404 Not Found` | `500 Internal Server Error`

---

## Monitoring Endpoints

### GET /api/processes/:id/metrics

Get performance metrics for a specific process.

**Parameters:**
- `id` (string, required) - Process identifier

**Response:**
```json
{
  "current": {
    "timestamp": "2024-01-15T10:30:00Z",
    "cpu_percent": 5.2,
    "memory_mb": 128.5,
    "uptime_seconds": 3600,
    "file_descriptors": 15,
    "status": "healthy"
  },
  "history": [
    {
      "timestamp": "2024-01-15T10:29:30Z",
      "cpu_percent": 4.8,
      "memory_mb": 125.2,
      "uptime_seconds": 3570,
      "file_descriptors": 14,
      "status": "healthy"
    }
  ]
}
```

**Status:** `200 OK` | `404 Not Found`

### GET /api/metrics

Get performance metrics for all processes.

**Response:**
```json
{
  "my_app": {
    "current": {
      "timestamp": "2024-01-15T10:30:00Z",
      "cpu_percent": 5.2,
      "memory_mb": 128.5,
      "uptime_seconds": 3600,
      "file_descriptors": 15,
      "status": "healthy"
    },
    "history": [...]
  },
  "worker": {
    "current": null,
    "history": []
  }
}
```

**Status:** `200 OK`

### GET /api/alerts

Get current system alerts for unhealthy processes.

**Response:**
```json
{
  "alerts": [
    {
      "process_id": "my_app",
      "type": "high_cpu",
      "message": "High CPU usage: 85.2%",
      "timestamp": "2024-01-15T10:30:00Z",
      "severity": "warning"
    }
  ]
}
```

**Alert Types:**
- `high_cpu` - CPU usage above 80%
- `high_memory` - Memory usage above 500MB

**Severity Levels:**
- `warning` - Requires attention
- `critical` - Immediate action needed

**Status:** `200 OK`

### DELETE /api/alerts

Clear all current alerts.

**Response:**
```json
{
  "status": "cleared"
}
```

**Status:** `200 OK`

---

## Platform Detection & Cross-Machine Monitoring

### GET /api/platform

Gets platform information for the current machine.

**Response:**
```json
{
  "platform": "darwin",
  "hostname": "zelan.local",
  "os_info": {
    "type": ["unix", "darwin"],
    "version": [21, 6, 0]
  }
}
```

**Status:** `200 OK`

### GET /api/platform/processes

Gets all running processes on the system (for debugging/monitoring).

**Response:**
```json
{
  "processes": [
    {
      "pid": 1234,
      "name": "bun",
      "command": "bun run start",
      "memory_kb": 51200,
      "cpu_percent": 2.5
    }
  ]
}
```

**Status:** `200 OK` | `500 Internal Server Error`

### GET /api/platform/processes/:name

Checks if a specific process is running and gets its information.

**URL Parameters:**
- `name` (string): Process name to search for (URL encoded)

**Response (Found):**
```json
{
  "pid": 1234,
  "name": "obs64.exe",
  "command": "C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe",
  "memory_kb": 204800,
  "cpu_percent": 5.2
}
```

**Response (Not Found):**
```json
{
  "error": "Process not found",
  "process_name": "nonexistent.exe"
}
```

**Status:** `200 OK` | `404 Not Found` | `500 Internal Server Error`

### POST /api/config/load

Loads machine-specific configuration and adds all processes to management.

**Request Body:**
```json
{
  "machine": "zelan"
}
```

**Response:**
```json
{
  "status": "loaded",
  "machine": "zelan",
  "processes_count": 3
}
```

**Status:** `200 OK` | `400 Bad Request`

### GET /api/health/detailed

Gets comprehensive health information for cross-machine monitoring.

**Response:**
```json
{
  "service": "nurvus",
  "version": "0.1.0",
  "timestamp": "2024-01-15T12:00:00Z",
  "platform": {
    "platform": "darwin",
    "hostname": "zelan.local"
  },
  "system": {
    "total_processes": 3,
    "running": 2,
    "stopped": 1,
    "failed": 0,
    "alerts": 1,
    "uptime": 3600
  },
  "processes": {
    "total": 5,
    "running": 3,
    "stopped": 2
  }
}
```

**Status:** `200 OK`

---

## Process Configuration

### JSON Configuration File

Processes can be pre-configured via a JSON file at `config/processes.json`:

```json
[
  {
    "id": "my_app",
    "name": "My Application",
    "command": "bun",
    "args": ["run", "start"],
    "cwd": "/path/to/app",
    "env": {
      "NODE_ENV": "production",
      "PORT": "3000"
    },
    "auto_restart": true,
    "max_restarts": 3,
    "restart_window": 60
  }
]
```

### Environment Variables

Configuration can be overridden with environment variables:

- `NURVUS_PORT` - HTTP server port (default: 4001)
- `NURVUS_CONFIG_FILE` - Path to process configuration file

---

## Process Status Values

- `running` - Process is active and monitored
- `stopped` - Process is configured but not running
- `failed` - Process exited unexpectedly
- `unknown` - Status cannot be determined

---

## Dashboard Integration Example

```javascript
// Fetch process list
const response = await fetch('http://localhost:4001/api/processes');
const { processes } = await response.json();

// Start a process
await fetch(`http://localhost:4001/api/processes/my_app/start`, {
  method: 'POST'
});

// Get real-time metrics
const metrics = await fetch('http://localhost:4001/api/metrics');
const processMetrics = await metrics.json();
```

---

## Error Examples

**Validation Error:**
```json
{
  "error": "\"name\" is required and must be a non-empty string"
}
```

**Process Not Found:**
```json
{
  "error": "Process not found"
}
```

**Start Failure:**
```json
{
  "error": "Failed to start process: command not found"
}
```
