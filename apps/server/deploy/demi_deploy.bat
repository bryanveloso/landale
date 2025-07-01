@echo off
rem Deploy script for demi (Windows - Worker Node)
setlocal enabledelayedexpansion

set NODE_NAME=demi
set DEPLOY_PATH=C:\landale
set RELEASE_PATH=_build\prod\rel\worker_windows

echo Deploying Windows worker node to %NODE_NAME%...

rem Environment variables for demi (Windows worker)
(
echo rem Worker node configuration
echo set RELEASE_NODE=server@demi
echo set PHX_SERVER=false
echo set WORKER_NODE=true
echo.
echo rem Cluster configuration
echo set CLUSTER_STRATEGY=Cluster.Strategy.Gossip
echo set CLUSTER_HOSTS=server@zelan,server@demi,server@saya,server@alys
echo set CLUSTER_IF_ADDR=100.0.0.0/8
echo set CLUSTER_PORT=45892
echo.
echo rem Logging
echo set LOG_LEVEL=info
) > deploy\env_demi.bat

echo Environment file created: deploy\env_demi.bat
echo.
echo Manual deployment steps for demi:
echo 1. Build Windows release on Windows machine: MIX_ENV=prod mix release worker_windows
echo 2. Copy release to %NODE_NAME%:%DEPLOY_PATH%
echo 3. Copy environment: deploy\env_demi.bat to %NODE_NAME%:%DEPLOY_PATH%\
echo 4. RDP to demi and run:
echo    cd %DEPLOY_PATH%
echo    env_demi.bat
echo    bin\worker.bat   rem Start worker node