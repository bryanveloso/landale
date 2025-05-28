# Landale Dashboard

Control dashboard for managing Landale overlays and stream settings.

## Features

- **System Status**: Real-time server health monitoring
- **Emote Rain Control**: Adjust physics settings, trigger bursts, clear all emotes
- **Activity Feed**: Live stream of all system events
- **Responsive Design**: Works on desktop and wide displays (1920x480)

## Development

```bash
# Start the dashboard
bun dev

# Build for production
bun build

# Type check
bun typecheck
```

## Configuration

Set the API key in `.env`:

```
VITE_CONTROL_API_KEY=your-secret-key
```

Or use the default development key: `landale-control-key`

## Usage

1. Make sure the Landale server is running
2. Start the dashboard with `bun dev`
3. Open http://localhost:5174 in your browser
4. The dashboard will automatically connect to the server on the same hostname

## Future Enhancements

This dashboard is designed to be extracted into a separate desktop app (Omnymate) in the future. The API-first design ensures easy migration when ready.
