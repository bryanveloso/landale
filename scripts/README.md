# Scripts

## Emote Caching

The `cache-emotes.ts` script downloads your Twitch channel emotes for use in overlays.

### Local Development

```bash
# From project root
bun run cache-emotes
```

### Docker Development

```bash
# Cache emotes in the Docker container
./scripts/docker-cache-emotes.sh
```

### How it works

1. Reads auth token from server's `twitch-token.json`
2. Fetches your channel's emotes from Twitch API
3. Downloads all sizes (28px, 56px, 112px) to `packages/overlays/public/emotes/`
4. Creates a manifest file tracking cached emotes

### Docker Volume

In Docker, emotes are stored in a named volume (`emotes_cache`) so they persist between container restarts. This avoids:

- Committing emote images to git
- Re-downloading emotes on every container rebuild
- Losing emotes when containers restart

The volume is automatically created by Docker Compose and mounted to the overlays container.
