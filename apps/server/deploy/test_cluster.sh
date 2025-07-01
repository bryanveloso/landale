#!/bin/bash
# Test script to verify cluster formation and process management

ZELAN_HOST="zelan.local"
API_PORT="4000"

echo "Testing Elixir cluster formation and process management..."

# Test 1: Check if controller node is reachable
echo "1. Testing controller node connectivity..."
if curl -s "http://$ZELAN_HOST:$API_PORT/health" > /dev/null; then
    echo "✅ Controller node (zelan) is reachable"
else
    echo "❌ Controller node (zelan) is not reachable"
    exit 1
fi

# Test 2: Check cluster status
echo ""
echo "2. Testing cluster status..."
CLUSTER_RESPONSE=$(curl -s "http://$ZELAN_HOST:$API_PORT/api/processes/cluster")
if echo "$CLUSTER_RESPONSE" | grep -q '"status":"success"'; then
    echo "✅ Cluster API is responding"
    
    # Count nodes
    NODE_COUNT=$(echo "$CLUSTER_RESPONSE" | jq -r '.nodes | length' 2>/dev/null || echo "unknown")
    echo "📊 Nodes in cluster: $NODE_COUNT"
    
    if [ "$NODE_COUNT" -eq 4 ]; then
        echo "✅ All 4 nodes are connected"
    else
        echo "⚠️  Expected 4 nodes, found $NODE_COUNT"
    fi
else
    echo "❌ Cluster API is not responding correctly"
    echo "Response: $CLUSTER_RESPONSE"
fi

# Test 3: Test process management (if demi is connected)
echo ""
echo "3. Testing cross-node process management..."
if echo "$CLUSTER_RESPONSE" | grep -q '"demi"'; then
    echo "✅ Demi node is connected, testing OBS control..."
    
    # Try to get OBS status on demi
    OBS_STATUS=$(curl -s "http://$ZELAN_HOST:$API_PORT/api/processes/demi/obs")
    if echo "$OBS_STATUS" | grep -q '"status":"success"'; then
        echo "✅ Can query OBS status on demi from zelan"
    else
        echo "⚠️  Cannot query OBS status on demi"
        echo "Response: $OBS_STATUS"
    fi
else
    echo "⚠️  Demi node not connected, skipping OBS test"
fi

# Test 4: List all processes across cluster
echo ""
echo "4. Listing all managed processes across cluster..."
if command -v jq > /dev/null; then
    echo "$CLUSTER_RESPONSE" | jq -r '.cluster | to_entries[] | "\(.key): \(.value | length) processes"'
else
    echo "Install jq for detailed process listing"
fi

echo ""
echo "Cluster test complete!"
echo ""
echo "Next steps if any tests failed:"
echo "1. Check Tailscale connectivity between nodes"
echo "2. Verify firewall rules allow port 45892 (cluster) and 4000 (API)"
echo "3. Check node logs for cluster formation issues"
echo "4. Ensure all nodes have correct CLUSTER_HOSTS environment variable"