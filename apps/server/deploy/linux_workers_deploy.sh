#!/bin/bash
# Deploy script for saya and alys (Linux - Worker Nodes)
set -e

DEPLOY_PATH="/opt/landale"
RELEASE_PATH="_build/prod/rel/worker"

echo "Deploying Linux worker nodes to saya and alys..."

# Environment variables for saya
cat > deploy/.env.saya << EOF
# Worker node configuration
RELEASE_NODE=server@saya
PHX_SERVER=false
WORKER_NODE=true

# Cluster configuration
CLUSTER_STRATEGY=Cluster.Strategy.Gossip
CLUSTER_HOSTS=server@zelan,server@demi,server@saya,server@alys
CLUSTER_IF_ADDR=100.0.0.0/8
CLUSTER_PORT=45892

# Logging
LOG_LEVEL=info
EOF

# Environment variables for alys
cat > deploy/.env.alys << EOF
# Worker node configuration
RELEASE_NODE=server@alys
PHX_SERVER=false
WORKER_NODE=true

# Cluster configuration
CLUSTER_STRATEGY=Cluster.Strategy.Gossip
CLUSTER_HOSTS=server@zelan,server@demi,server@saya,server@alys
CLUSTER_IF_ADDR=100.0.0.0/8
CLUSTER_PORT=45892

# Logging
LOG_LEVEL=info
EOF

echo "Environment files created:"
echo "  deploy/.env.saya"
echo "  deploy/.env.alys"
echo ""
echo "Manual deployment steps for Linux workers:"
echo "For saya:"
echo "1. Copy release: $RELEASE_PATH to saya:$DEPLOY_PATH"
echo "2. Copy environment: deploy/.env.saya to saya:$DEPLOY_PATH/.env"
echo "3. SSH to saya and run: cd $DEPLOY_PATH && ./bin/worker"
echo ""
echo "For alys:"
echo "1. Copy release: $RELEASE_PATH to alys:$DEPLOY_PATH"
echo "2. Copy environment: deploy/.env.alys to alys:$DEPLOY_PATH/.env"
echo "3. SSH to alys and run: cd $DEPLOY_PATH && ./bin/worker"