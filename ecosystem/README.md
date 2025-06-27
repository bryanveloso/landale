# Service Management Configuration

This directory contains configuration for managing Landale services across different machines.

## Files

- **`zelan.config.cjs`** - PM2 config for Mac Studio (zelan)
  - Runs: landale-phononmaser
  
- **`saya.docker-compose.md`** - Docker instructions for Mac Mini (saya)
  - Runs: landale-server, landale-overlays, postgres

## Service Management

### Mac Mini (saya) - Docker Compose
```bash
# Services managed by Docker
cd /opt/landale
docker compose up -d      # Start all
docker compose ps         # Check status
docker compose logs -f    # View logs
```

### Mac Studio (zelan) - PM2
```bash
# Services managed by PM2
pm2 start ecosystem/zelan.config.cjs
pm2 status
pm2 logs
```

## Why Separate Files?

- Prevents PM2 from trying to start services that aren't on that machine
- Clearer configuration management
- Machine-specific environment variables
- Easier to maintain

## Deployment

The `manage-services.ts` script automatically uses the correct ecosystem file based on the machine name.