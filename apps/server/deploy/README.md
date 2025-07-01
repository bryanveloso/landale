# Landale Distributed Cluster Deployment

This directory contains scripts and configurations for deploying the Landale distributed Elixir cluster across 4 machines.

## Architecture

- **zelan** (Mac Studio): Controller node with full services + web API
- **demi** (Windows): Worker node with process supervision (OBS control)
- **saya** (Linux): Worker node with process supervision  
- **alys** (Linux): Worker node with process supervision

## Prerequisites

1. **Tailscale network** configured on all machines (100.x.x.x range)
2. **Elixir/Erlang** installed on build machine only
3. **Database** accessible from zelan (PostgreSQL)
4. **Firewall** ports open:
   - 4000: Phoenix server (zelan only)
   - 45892: Cluster communication (all nodes)
   - 8080: IronMON TCP (zelan only)

## Quick Deployment

### 1. Build Releases

```bash
./build_releases.sh
```

### 2. Deploy Controller Node (zelan)

```bash
./zelan_deploy.sh
# Follow the manual steps printed by the script
```

### 3. Deploy Linux Workers (saya, alys)

```bash
./linux_workers_deploy.sh
# Follow the manual steps printed by the script
```

### 4. Deploy Windows Worker (demi)

```bash
# On Windows machine with Elixir installed:
MIX_ENV=prod mix release worker_windows

# Then run:
demi_deploy.bat
# Follow the manual steps printed by the script
```

### 5. Test Cluster

```bash
./test_cluster.sh
```

## Node-Specific Configuration

### zelan (Controller)
- Runs full Phoenix application
- Database access required
- Hosts REST API on port 4000
- Manages cluster coordination

### demi (Windows Worker)
- Manages Windows processes (OBS, StreamDeck, etc.)
- No database required
- Connects to cluster for process management

### saya/alys (Linux Workers)
- Manage Linux services (nginx, postgresql, etc.)
- No database required
- Connect to cluster for process management

## Environment Variables

Each node requires specific environment variables. See the deployment scripts for complete configurations.

### Critical Variables

- `RELEASE_NODE`: Node identifier (e.g., server@zelan)
- `WORKER_NODE`: true for workers, false for controller
- `CLUSTER_HOSTS`: Comma-separated list of all nodes
- `CLUSTER_IF_ADDR`: Network interface (100.0.0.0/8 for Tailscale)

## Process Management

Once deployed, you can manage processes across the cluster:

### REST API Examples

```bash
# Get cluster status
curl http://zelan.local:4000/api/processes/cluster

# Start OBS on Windows machine from any node
curl -X POST http://zelan.local:4000/api/processes/demi/obs/start

# Stop a Linux service from any node  
curl -X POST http://zelan.local:4000/api/processes/saya/nginx/stop

# Get process status
curl http://zelan.local:4000/api/processes/demi/obs
```

### Elixir Console Examples

```elixir
# Connect to running node
iex --name admin@zelan --cookie landale_cluster

# Get cluster nodes
Node.list()

# Start process on remote node
ProcessSupervisor.start_process("demi", "obs")

# Get cluster-wide status
ProcessSupervisor.cluster_status()
```

## Troubleshooting

### Cluster Formation Issues

1. **Check Tailscale connectivity**:
   ```bash
   ping 100.x.x.x  # Test each node
   ```

2. **Verify cluster communication**:
   ```bash
   telnet zelan.local 45892
   ```

3. **Check node logs**:
   ```bash
   tail -f /opt/landale/log/erlang.log.*
   ```

### Process Management Issues

1. **Verify platform supervisor initialization**
2. **Check process definitions in supervisor modules**
3. **Test platform-specific commands manually**

## Security Notes

- Cluster uses Erlang distribution protocol (ensure trusted network)
- No authentication between cluster nodes (Tailscale provides encryption)
- REST API has no built-in authentication (add reverse proxy if needed)

## Monitoring

- Phoenix LiveDashboard available at: http://zelan.local:4000/dashboard
- Process events broadcast via Phoenix PubSub
- Logs collected per-node in respective log directories