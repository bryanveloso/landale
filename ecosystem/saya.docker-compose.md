# Saya (Mac Mini) Services

Services on Saya are managed by Docker Compose, not PM2.

## Start Services
```bash
cd /opt/landale
docker compose up -d
```

## Check Status
```bash
docker compose ps
```

## View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f server
docker compose logs -f overlays
```

## Restart Services
```bash
# All services
docker compose restart

# Specific service
docker compose restart server
```

## Deploy Updates
```bash
cd /opt/landale
git pull
docker compose build
docker compose up -d
```

## Why Docker instead of PM2?
- Already configured with health checks
- Handles database dependencies
- Isolated environments
- Automatic restarts built-in
- Better for PostgreSQL management