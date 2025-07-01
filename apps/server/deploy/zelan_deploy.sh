#!/bin/bash
# Deploy script for zelan (Mac Studio - Controller Node)
set -e

NODE_NAME="zelan"
DEPLOY_PATH="/opt/landale"
RELEASE_PATH="_build/prod/rel/server"

echo "Deploying controller node to $NODE_NAME..."

# Environment variables for zelan (controller)
cat > deploy/.env.zelan << EOF
# Controller node configuration
RELEASE_NODE=server@zelan
PHX_SERVER=true
WORKER_NODE=false

# Database configuration (use localhost since PostgreSQL runs on zelan)
DATABASE_URL=ecto://postgres:postgres@localhost/landale_prod
POOL_SIZE=10

# Phoenix configuration (use Tailscale hostname)
SECRET_KEY_BASE=$(mix phx.gen.secret)
PHX_HOST=zelan
PORT=4000
BIND_IP=100.112.39.113

# Cluster configuration (use Tailscale interface and node names)
CLUSTER_STRATEGY=Cluster.Strategy.Gossip
CLUSTER_HOSTS=server@zelan,server@demi,server@saya,server@alys
CLUSTER_IF_ADDR=utun6
CLUSTER_PORT=45892

# Twitch configuration (if needed)
# TWITCH_CLIENT_ID=your_client_id
# TWITCH_CLIENT_SECRET=your_client_secret
# TWITCH_USER_ID=your_user_id

# IronMON TCP port
IRONMON_TCP_PORT=8080
EOF

echo "Environment file created: deploy/.env.zelan"
echo ""
echo "Manual deployment steps for zelan:"
echo "1. Copy release: $RELEASE_PATH to $NODE_NAME:$DEPLOY_PATH"
echo "2. Copy environment: deploy/.env.zelan to $NODE_NAME:$DEPLOY_PATH/.env"
echo "3. SSH to zelan and run:"
echo "   cd $DEPLOY_PATH"
echo "   ./bin/migrate  # Run database migrations"
echo "   ./bin/server   # Start controller node"