#!/bin/bash
# Script to cache emotes inside Docker container

echo "Caching emotes in Docker container..."

# Run the cache script inside the server container
docker compose exec server bun run cache-emotes

echo "Emotes cached successfully!"