# Server

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Twitch Token Management

The server includes a professional CLI for managing Twitch OAuth tokens with production Docker support.

### Quick Commands

```bash
# Interactive token creation (development)
mix twitch.token

# Refresh existing tokens (Docker-friendly)
mix twitch.token refresh

# Check token status and expiration
mix twitch.token status

# Full help and usage guide
mix twitch.token help
```

### Production Docker Workflows

#### Initial Setup (One-time)

1. **Create tokens on development machine:**
   ```bash
   mix twitch.token
   ```

2. **Copy tokens to production:**
   ```bash
   rsync ./data/twitch_tokens* server:/app/data/
   ```

#### Ongoing Maintenance

```bash
# Check if tokens are expiring soon
docker exec landale-server mix twitch.token status

# Refresh tokens when they expire (no browser required)
docker exec landale-server mix twitch.token refresh
```

#### Automated Monitoring

Add to crontab for automatic token refresh:

```bash
# Check every 30 minutes and auto-refresh if needed
*/30 * * * * docker exec landale-server bash -c \
  "mix twitch.token status | grep -q 'expires soon' && mix twitch.token refresh"
```

### Environment Setup

Required environment variables:
- `TWITCH_CLIENT_ID` - Your Twitch application client ID  
- `TWITCH_CLIENT_SECRET` - Your Twitch application client secret

Get these from: https://dev.twitch.tv/console/apps

### File Locations

- **Development:** `./data/twitch_tokens.dets` + `./data/twitch_tokens_backup.json`
- **Production:** `/app/data/twitch_tokens.dets` + `/app/data/twitch_tokens_backup.json`

For detailed help and troubleshooting, run: `mix twitch.token help`

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
