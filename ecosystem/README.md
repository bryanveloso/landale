# Service Management Configuration

This directory contains configuration for managing Landale services across different machines.

## Files

- **`zelan.supervisord.conf`** - Supervisor config for Mac Studio (zelan)
  - Runs: phononmaser, analysis
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

### Mac Studio (zelan) - Supervisor

```bash
# Services managed by Supervisor
supervisord -c ecosystem/zelan.supervisord.conf
supervisorctl -s unix:///tmp/landale-supervisor.sock status
supervisorctl -s unix:///tmp/landale-supervisor.sock tail -f phononmaser
```

## Why Separate Files?

- Prevents process managers from trying to start services that aren't on that machine
- Clearer configuration management
- Machine-specific environment variables
- Easier to maintain

## Deployment

The `manage-services.ts` script automatically uses the correct ecosystem file based on the machine name.
