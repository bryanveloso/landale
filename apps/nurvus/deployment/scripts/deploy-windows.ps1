# Nurvus Windows Deployment Script
# For Demi (Windows PC) and Alys (Windows VM)

param(
    [string]$MachineName = (hostname),
    [string]$TargetDir = "C:\nurvus",
    [string]$ServiceName = "Nurvus"
)

Write-Host "🚀 Deploying Nurvus to $MachineName" -ForegroundColor Green
Write-Host "   Target: $TargetDir"
Write-Host "   Service: $ServiceName"

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "⚠️  Not running as administrator. Some operations may fail." -ForegroundColor Yellow
}

# Step 1: Check for release or build if on build machine
if (Test-Path "_build\prod\rel\nurvus") {
    Write-Host "📦 Using existing release..." -ForegroundColor Blue
} elseif (Get-Command "mix" -ErrorAction SilentlyContinue) {
    Write-Host "📦 Building release (Elixir detected)..." -ForegroundColor Blue
    $env:MIX_ENV = "prod"
    mix deps.get --only prod
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    mix compile
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    mix release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "❌ No release found and Elixir not installed." -ForegroundColor Red
    Write-Host "Either:" -ForegroundColor Yellow
    Write-Host "1. Copy pre-built release from build machine, OR" -ForegroundColor Yellow
    Write-Host "2. Install Elixir to build locally" -ForegroundColor Yellow
    exit 1
}

# Step 2: Create target directory
Write-Host "📁 Creating target directory..." -ForegroundColor Blue
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
New-Item -ItemType Directory -Force -Path "$TargetDir\config" | Out-Null
New-Item -ItemType Directory -Force -Path "$TargetDir\logs" | Out-Null

# Step 3: Copy release files
Write-Host "📋 Copying release files..." -ForegroundColor Blue
Copy-Item -Recurse -Force "_build\prod\rel\nurvus\*" $TargetDir

# Step 4: Copy machine-specific configuration
$configFile = "config\$MachineName.json"
if (Test-Path $configFile) {
    Write-Host "⚙️  Copying $MachineName configuration..." -ForegroundColor Blue
    Copy-Item $configFile "$TargetDir\config\"
    Copy-Item $configFile "$TargetDir\config\processes.json"
} else {
    Write-Host "⚠️  No specific config for $MachineName, using default" -ForegroundColor Yellow
    if (Test-Path "config\processes.json") {
        Copy-Item "config\processes.json" "$TargetDir\config\"
    }
}

# Step 5: Install as Windows service using NSSM
Write-Host "🔧 Installing Windows service..." -ForegroundColor Blue

# Check if NSSM is available
if (-not (Get-Command "nssm" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ NSSM not found. Installing with chocolatey..." -ForegroundColor Red
    
    if (Get-Command "choco" -ErrorAction SilentlyContinue) {
        choco install nssm -y
    } else {
        Write-Host "❌ Chocolatey not found. Please install NSSM manually:" -ForegroundColor Red
        Write-Host "   Download from: https://nssm.cc/download"
        Write-Host "   Or install chocolatey: https://chocolatey.org/install"
        exit 1
    }
}

# Find Mix executable
$mixPath = (Get-Command "mix" -ErrorAction SilentlyContinue).Source
if (-not $mixPath) {
    Write-Host "❌ Mix not found in PATH" -ForegroundColor Red
    exit 1
}

# Remove existing service if it exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "🗑️  Removing existing service..." -ForegroundColor Yellow
    nssm stop $ServiceName
    nssm remove $ServiceName confirm
}

# Install new service
Write-Host "📦 Installing service..." -ForegroundColor Blue
nssm install $ServiceName $mixPath
nssm set $ServiceName Parameters "run --no-halt"
nssm set $ServiceName AppDirectory $TargetDir
nssm set $ServiceName DisplayName "Nurvus Process Manager"
nssm set $ServiceName Description "PM2-like process manager for streaming setup"

# Set environment variables
nssm set $ServiceName AppEnvironmentExtra "MIX_ENV=prod" "NURVUS_PORT=4001" "NURVUS_CONFIG_FILE=$TargetDir\config\processes.json"

# Set startup type to automatic
nssm set $ServiceName Start SERVICE_AUTO_START

# Set log files
nssm set $ServiceName AppStdout "$TargetDir\logs\stdout.log"
nssm set $ServiceName AppStderr "$TargetDir\logs\stderr.log"

# Step 6: Create helper scripts
Write-Host "📝 Creating helper scripts..." -ForegroundColor Blue

# Start script
@"
@echo off
cd /d "$TargetDir"
bin\nurvus.bat start
"@ | Out-File -FilePath "$TargetDir\start.bat" -Encoding ASCII

# Stop script
@"
@echo off
cd /d "$TargetDir"
bin\nurvus.bat stop
"@ | Out-File -FilePath "$TargetDir\stop.bat" -Encoding ASCII

# Status script
@"
@echo off
cd /d "$TargetDir"
bin\nurvus.bat pid
"@ | Out-File -FilePath "$TargetDir\status.bat" -Encoding ASCII

# Service management script
@"
@echo off
echo Nurvus Service Management
echo ========================
echo.
echo 1. Start Service
echo 2. Stop Service  
echo 3. Restart Service
echo 4. Service Status
echo 5. Service Logs
echo 6. Exit
echo.
set /p choice="Enter choice (1-6): "

if "%choice%"=="1" (
    net start $ServiceName
) else if "%choice%"=="2" (
    net stop $ServiceName
) else if "%choice%"=="3" (
    net stop $ServiceName
    timeout /t 3 /nobreak > nul
    net start $ServiceName
) else if "%choice%"=="4" (
    sc query $ServiceName
) else if "%choice%"=="5" (
    type "$TargetDir\logs\stdout.log"
) else if "%choice%"=="6" (
    exit
) else (
    echo Invalid choice
)
pause
"@ | Out-File -FilePath "$TargetDir\manage.bat" -Encoding ASCII

# Step 7: Test installation
Write-Host "🧪 Testing installation..." -ForegroundColor Blue
if (Test-Path "$TargetDir\bin\nurvus.bat") {
    Write-Host "✅ Binary is available" -ForegroundColor Green
} else {
    Write-Host "❌ Binary not found" -ForegroundColor Red
    exit 1
}

# Step 8: Display completion message
Write-Host ""
Write-Host "🎉 Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Test the installation:"
Write-Host "   cd $TargetDir"
Write-Host "   .\start.bat"
Write-Host "   curl http://localhost:4001/health"
Write-Host "   .\stop.bat"
Write-Host ""
Write-Host "2. Start the Windows service:"
Write-Host "   net start $ServiceName"
Write-Host ""
Write-Host "3. Check service status:"
Write-Host "   sc query $ServiceName"
Write-Host "   curl http://localhost:4001/health"
Write-Host ""
Write-Host "4. Manage service:"
Write-Host "   .\manage.bat"
Write-Host ""
Write-Host "📚 See DEPLOYMENT.md for more information" -ForegroundColor Blue