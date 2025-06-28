# Agent Deployment Guide

This guide explains how to deploy Landale agents on each machine.

## macOS Agents (saya, zelan)

### 1. Install Bun (if not already installed)

```bash
curl -fsSL https://bun.sh/install | bash
```

### 2. Clone the repository (or copy agent files)

```bash
# Option 1: Clone full repository
git clone https://github.com/yourusername/landale.git
cd landale

# Option 2: Copy just the agent package
# Copy the packages/agent directory to the target machine
```

### 3. Install dependencies

```bash
cd packages/agent
bun install
```

### 4. Create a launchd service (macOS)

Create `/Library/LaunchDaemons/com.landale.agent.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.landale.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bun</string>
        <string>run</string>
        <string>/path/to/landale/packages/agent/src/agents/MACHINE-agent.ts</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/landale-agent.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/landale-agent-error.log</string>
</dict>
</plist>
```

Replace `MACHINE` with `saya` or `zelan` as appropriate.

### 5. Load the service

```bash
sudo launchctl load /Library/LaunchDaemons/com.landale.agent.plist
```

### 6. Check status

```bash
sudo launchctl list | grep landale
tail -f /var/log/landale-agent.log
```

## Windows Agent (demi)

### 1. Copy PowerShell scripts

Copy these files to `C:\landale\agent\`:
- `windows-agent.ps1`
- `obs-websocket.ps1`

### 2. Create a scheduled task

Run PowerShell as Administrator:

```powershell
# Create the scheduled task
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\landale\agent\windows-agent.ps1"

$trigger = New-ScheduledTaskTrigger -AtStartup

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName "Landale Agent" `
    -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings
```

### 3. Start the agent

```powershell
Start-ScheduledTask -TaskName "Landale Agent"
```

### 4. Check logs

```powershell
Get-ScheduledTaskInfo -TaskName "Landale Agent"
# Check Windows Event Viewer for detailed logs
```

## Configuration

Each agent needs to know the server URL. Update the agent files with the correct Tailscale hostname:

- For macOS agents: Edit the `serverUrl` in the agent TypeScript files
- For Windows agent: Pass `-ServerUrl` parameter or edit the default in the PowerShell script

## Testing

After deployment, verify the agents are connected:

1. Check the server logs to see agent connections
2. Use the dashboard to view agent status
3. Test a simple command like getting system info

## Troubleshooting

### macOS
- Check launchd logs: `sudo launchctl error com.landale.agent`
- Verify Bun is in PATH: `which bun`
- Check file permissions

### Windows
- Run the PowerShell script manually to see errors
- Check Windows Firewall isn't blocking connections
- Verify PowerShell execution policy allows scripts

### Both
- Ensure Tailscale is running and connected
- Verify the server is accessible from the agent machine
- Check network connectivity between machines