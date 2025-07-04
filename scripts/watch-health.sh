#!/bin/bash

# Simple health status watcher - run this in a terminal during streams
# Usage: ./scripts/watch-health.sh

clear
echo "🎮 LANDALE OVERLAY SYSTEM MONITOR"
echo "================================="
echo ""

while true; do
    # Move cursor to home position (don't clear screen to avoid flicker)
    tput cup 3 0

    if response=$(curl -s -m 2 http://localhost:7175/health 2>/dev/null); then
        status=$(echo "$response" | jq -r .status)
        uptime=$(echo "$response" | jq -r .uptime | cut -d. -f1)
        version=$(echo "$response" | jq -r .version)

        if [ "$status" = "ok" ]; then
            hours=$((uptime / 3600))
            minutes=$(((uptime % 3600) / 60))

            echo "✅ Status: ONLINE                    "
            echo "⏱️  Uptime: ${hours}h ${minutes}m     "
            echo "📦 Version: $version                 "
            echo ""
            echo "Press Ctrl+C to exit                 "
        else
            echo "⚠️  Status: DEGRADED                 "
            echo "                                     "
            echo "                                     "
            echo ""
            echo "Press Ctrl+C to exit                 "
        fi
    else
        echo "❌ Status: OFFLINE                   "
        echo "                                     "
        echo "Cannot connect to overlay server     "
        echo ""
        echo "Press Ctrl+C to exit                 "
    fi

    sleep 5
done
