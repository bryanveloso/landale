#!/bin/bash
# Script to cache emotes inside Docker container

echo "Caching emotes in Docker container..."

# Run the cache script inside the container
docker compose exec app bun run cache-emotes

echo "Emotes cached successfully!"