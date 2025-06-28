# Windows Agent for Landale
# This PowerShell script runs as the agent on Windows machines

param(
    [string]$AgentId = "demi",
    [string]$AgentName = "Demi OBS Agent",
    [string]$ServerUrl = "http://saya:7175",
    [string]$OBSPassword = ""
)

$ErrorActionPreference = "Stop"

# Configuration
$config = @{
    Id = $AgentId
    Name = $AgentName
    Host = $env:COMPUTERNAME
    ServerUrl = $ServerUrl
    OBSPassword = $OBSPassword
    ReconnectInterval = 5000
    HeartbeatInterval = 30000
}

# Agent state
$ws = $null
$obsConnected = $false
$capabilities = @(
    @{
        name = "obs"
        description = "OBS Studio control"
        actions = @("start", "stop", "status", "connect", "scenes", "switchScene", "streaming", "startStream", "stopStream")
    },
    @{
        name = "process"
        description = "Process management"
        actions = @("list", "start", "stop", "status")
    },
    @{
        name = "system"
        description = "System information"
        actions = @("info", "metrics")
    }
)

# Logging
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# OBS WebSocket functions
function Connect-OBS {
    try {
        if (Test-Path "C:\Program Files\obs-studio\bin\64bit\obs64.exe") {
            Import-Module "$PSScriptRoot\obs-websocket.ps1" -Force
            $script:obsConnected = Connect-OBSWebSocket -Password $config.OBSPassword
            return $obsConnected
        }
        return $false
    } catch {
        Write-Log "Failed to connect to OBS: $_" "ERROR"
        return $false
    }
}

function Get-OBSStatus {
    $process = Get-Process obs64 -ErrorAction SilentlyContinue
    $status = @{
        running = $null -ne $process
        connected = $script:obsConnected
        pid = if ($process) { $process.Id } else { $null }
    }
    
    if ($status.connected) {
        try {
            $streamStatus = Get-OBSStreamStatus
            $status.streaming = $streamStatus.streaming
            $status.recording = $streamStatus.recording
            $status.currentScene = (Get-OBSCurrentScene).name
        } catch {
            $status.connected = $false
            $script:obsConnected = $false
        }
    }
    
    return $status
}

function Start-OBS {
    $obsPath = "C:\Program Files\obs-studio\bin\64bit\obs64.exe"
    if (Test-Path $obsPath) {
        Start-Process $obsPath
        Start-Sleep -Seconds 5
        Connect-OBS
        return $true
    }
    return $false
}

function Stop-OBS {
    $process = Get-Process obs64 -ErrorAction SilentlyContinue
    if ($process) {
        $process | Stop-Process -Force
        $script:obsConnected = $false
        return $true
    }
    return $false
}

# Process management
function Get-ProcessList {
    Get-Process | Where-Object {
        $_.ProcessName -match "obs|streamlabs|xsplit|game|steam|epic"
    } | Select-Object Id, ProcessName, CPU, WorkingSet64 | ForEach-Object {
        @{
            name = $_.ProcessName
            pid = $_.Id
            cpu = [math]::Round($_.CPU, 2)
            memory = [math]::Round($_.WorkingSet64 / 1MB, 2)
            status = "running"
        }
    }
}

function Get-ProcessStatus {
    param($ProcessName)
    $process = Get-Process $ProcessName -ErrorAction SilentlyContinue
    if ($process) {
        return @{
            name = $ProcessName
            pid = $process.Id
            status = "running"
            cpu = [math]::Round($process.CPU, 2)
            memory = [math]::Round($process.WorkingSet64 / 1MB, 2)
        }
    }
    return @{
        name = $ProcessName
        status = "stopped"
    }
}

# System information
function Get-SystemInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    
    @{
        hostname = $env:COMPUTERNAME
        os = "$($os.Caption) $($os.Version)"
        uptime = (Get-Date) - $os.LastBootUpTime
        manufacturer = $computer.Manufacturer
        model = $computer.Model
    }
}

function Get-SystemMetrics {
    $cpu = Get-CimInstance Win32_Processor
    $memory = Get-CimInstance Win32_OperatingSystem
    
    $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
    
    @{
        cpu = @{
            usage = [math]::Round($cpuUsage, 2)
            cores = $cpu.NumberOfCores
            threads = $cpu.NumberOfLogicalProcessors
        }
        memory = @{
            total = $memory.TotalVisibleMemorySize * 1KB
            free = $memory.FreePhysicalMemory * 1KB
            used = ($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) * 1KB
            percentage = [math]::Round((($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / $memory.TotalVisibleMemorySize) * 100, 2)
        }
    }
}

# Command handlers
function Handle-Command {
    param($Command)
    
    try {
        $parts = $Command.action -split '\.'
        $capability = $parts[0]
        $action = $parts[1]
        
        switch ($capability) {
            "obs" {
                switch ($action) {
                    "start" { 
                        $result = Start-OBS
                        return @{ success = $result }
                    }
                    "stop" { 
                        $result = Stop-OBS
                        return @{ success = $result }
                    }
                    "status" { 
                        return Get-OBSStatus
                    }
                    "connect" {
                        $result = Connect-OBS
                        return @{ success = $result }
                    }
                    "scenes" {
                        if ($obsConnected) {
                            return Get-OBSScenes
                        }
                        throw "OBS not connected"
                    }
                    "switchScene" {
                        if ($obsConnected -and $Command.params.scene) {
                            Set-OBSCurrentScene -Name $Command.params.scene
                            return @{ success = $true }
                        }
                        throw "OBS not connected or scene not specified"
                    }
                    "streaming" {
                        if ($obsConnected) {
                            return Get-OBSStreamStatus
                        }
                        throw "OBS not connected"
                    }
                    "startStream" {
                        if ($obsConnected) {
                            Start-OBSStream
                            return @{ success = $true }
                        }
                        throw "OBS not connected"
                    }
                    "stopStream" {
                        if ($obsConnected) {
                            Stop-OBSStream
                            return @{ success = $true }
                        }
                        throw "OBS not connected"
                    }
                }
            }
            "process" {
                switch ($action) {
                    "list" { return Get-ProcessList }
                    "status" { 
                        if ($Command.params.name) {
                            return Get-ProcessStatus -ProcessName $Command.params.name
                        }
                        throw "Process name required"
                    }
                }
            }
            "system" {
                switch ($action) {
                    "info" { return Get-SystemInfo }
                    "metrics" { return Get-SystemMetrics }
                }
            }
        }
        
        throw "Unknown command: $($Command.action)"
    } catch {
        Write-Log "Command failed: $_" "ERROR"
        throw
    }
}

# WebSocket connection
function Connect-Server {
    try {
        $wsUrl = $config.ServerUrl -replace "^http", "ws"
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $uri = New-Object System.Uri("$wsUrl/agent")
        
        $cts = New-Object System.Threading.CancellationTokenSource
        $connectTask = $ws.ConnectAsync($uri, $cts.Token)
        
        while (!$connectTask.IsCompleted) {
            Start-Sleep -Milliseconds 100
        }
        
        if ($ws.State -eq 'Open') {
            Write-Log "Connected to server"
            $script:ws = $ws
            Send-Status
            return $true
        }
    } catch {
        Write-Log "Failed to connect: $_" "ERROR"
    }
    return $false
}

function Send-Message {
    param($Message)
    
    if ($null -eq $ws -or $ws.State -ne 'Open') {
        return
    }
    
    try {
        $json = $Message | ConvertTo-Json -Depth 10
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $buffer = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
        
        $sendTask = $ws.SendAsync($buffer, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
        while (!$sendTask.IsCompleted) {
            Start-Sleep -Milliseconds 10
        }
    } catch {
        Write-Log "Failed to send message: $_" "ERROR"
    }
}

function Send-Status {
    $status = @{
        type = "status"
        data = @{
            id = $config.Id
            name = $config.Name
            host = $config.Host
            status = "online"
            lastSeen = Get-Date -Format "o"
            capabilities = $capabilities
            metrics = Get-SystemMetrics
        }
    }
    Send-Message $status
}

function Receive-Messages {
    $buffer = New-Object System.ArraySegment[byte] -ArgumentList @(,@([byte[]]::new(4096)))
    
    while ($ws.State -eq 'Open') {
        try {
            $receiveTask = $ws.ReceiveAsync($buffer, [System.Threading.CancellationToken]::None)
            while (!$receiveTask.IsCompleted) {
                Start-Sleep -Milliseconds 10
            }
            
            if ($receiveTask.Result.MessageType -eq 'Text') {
                $json = [System.Text.Encoding]::UTF8.GetString($buffer.Array, 0, $receiveTask.Result.Count)
                $command = $json | ConvertFrom-Json
                
                Write-Log "Received command: $($command.action)"
                
                $response = @{
                    type = "response"
                    data = @{
                        commandId = $command.id
                        timestamp = Get-Date -Format "o"
                    }
                }
                
                try {
                    $result = Handle-Command $command
                    $response.data.success = $true
                    $response.data.result = $result
                } catch {
                    $response.data.success = $false
                    $response.data.error = $_.ToString()
                }
                
                Send-Message $response
            }
        } catch {
            Write-Log "Error receiving message: $_" "ERROR"
            break
        }
    }
}

# Main loop
Write-Log "Starting Windows Agent: $($config.Name)"

# Try to connect to OBS if it's running
if (Get-Process obs64 -ErrorAction SilentlyContinue) {
    Connect-OBS
}

# Main connection loop
while ($true) {
    try {
        if (Connect-Server) {
            # Start heartbeat
            $heartbeatTimer = [System.Timers.Timer]::new($config.HeartbeatInterval)
            Register-ObjectEvent -InputObject $heartbeatTimer -EventName Elapsed -Action {
                Send-Status
            } | Out-Null
            $heartbeatTimer.Start()
            
            # Receive messages
            Receive-Messages
            
            # Cleanup
            $heartbeatTimer.Stop()
            $heartbeatTimer.Dispose()
        }
    } catch {
        Write-Log "Connection error: $_" "ERROR"
    }
    
    if ($null -ne $ws) {
        $ws.Dispose()
        $ws = $null
    }
    
    Write-Log "Reconnecting in $($config.ReconnectInterval)ms..."
    Start-Sleep -Milliseconds $config.ReconnectInterval
}