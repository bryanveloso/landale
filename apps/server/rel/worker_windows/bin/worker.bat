@echo off
cd /d "%~dp0"

rem Set node name based on hostname or environment
if "%RELEASE_NODE%"=="" set RELEASE_NODE=server@%COMPUTERNAME%

rem Set cluster configuration
if "%CLUSTER_STRATEGY%"=="" set CLUSTER_STRATEGY=Cluster.Strategy.Gossip
if "%CLUSTER_HOSTS%"=="" set CLUSTER_HOSTS=server@zelan,server@demi,server@saya,server@alys

rem Worker node configuration - disable web server
set PHX_SERVER=false
set WORKER_NODE=true

rem Start the worker
server.bat start