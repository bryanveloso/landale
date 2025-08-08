# Landale Overlays

Real-time streaming overlays for OBS, built with SolidJS and powered by Phoenix WebSockets.

**Last Updated**: 2025-08-08

## Overview

The overlays app provides sophisticated, animated streaming overlays that respond to:

- Twitch events (follows, subscriptions, cheers, raids)
- Audio transcription and analysis
- Chat interactions
- Stream state changes

## Architecture

- **Frontend**: SolidJS with GSAP animations
- **State Management**: SolidJS signals and stores
- **Communication**: Phoenix WebSocket channels
- **Audio**: Howler.js with -16 LUFS normalization
- **Styling**: Tailwind CSS

## Key Features

### 🔔 Notification System

Complete notification pipeline with:

- Priority-based queuing
- Audio synchronization
- Type-safe configuration
- Debug interface

[Full Documentation →](./docs/notification-system.md)

### 🎨 Layer Orchestration

Three-layer animation system:

- Foreground (highest priority)
- Midground (notifications)
- Background (ambient)

State machine: `hidden → entering → active → interrupted → exiting`

### 🔊 Audio Management

- Preload pools (3 instances per sound)
- Volume normalization (-16 LUFS)
- Click-to-enable for browser policies
- Persistent volume settings

### 🐛 Debug Interface

Comprehensive debugging via `window.debug`:

```javascript
debug.notification.test.testFollow()
debug.audio.setVolume(0.5)
debug.burst.stress(30000)
```

[Debug Interface Guide →](./docs/debug-interface.md)

## Quick Start

### Installation

```bash
bun install
```

### Development

```bash
bun dev
# Opens at http://localhost:5173
```

### Production Build

```bash
bun run build
# Output in dist/ folder
```

### Testing

```bash
bun test
bun test:watch
```

## Configuration

### Notification Configuration

Place custom configs in `/public/config/notifications.json`:

```json
{
  "version": "1.0",
  "configs": [
    {
      "id": "follow-default",
      "condition": { "type": "channel.follow" },
      "audio": "/audio/notifications/follow.ogg",
      "priority": 5,
      "duration": 5000
    }
  ]
}
```

[Configuration Guide →](./docs/notification-configuration.md)

### Audio Files

- **Location**: `/public/audio/notifications/`
- **Format**: OGG Vorbis (preferred) or MP3
- **Normalization**: -16 LUFS

## OBS Integration

### Browser Source Settings

- **URL**: `http://localhost:5173/omnibar`
- **Width**: 1920
- **Height**: 1080
- **FPS**: 60
- **Custom CSS**: (optional)

### Available Routes

- `/omnibar` - Main notification overlay
- `/emote-rain` - Emote animations
- `/after-dark` - Flying toasters screensaver

## Documentation

- [Notification System](./docs/notification-system.md) - Complete notification pipeline
- [API Reference](./docs/notification-api-reference.md) - Developer integration guide
- [Configuration](./docs/notification-configuration.md) - JSON config schemas
- [Debug Interface](./docs/debug-interface.md) - Testing and debugging
- [GSAP Migration](./docs/framer-motion-to-gsap-guide.md) - Animation framework guide

## Common Tasks

### Test Notifications

```javascript
// In browser console
debug.notification.test.testFollow()
debug.notification.test.testTier3Sub()
debug.notification.test.test420Bits()
```

### Check Queue Status

```javascript
debug.notification.queue.getStatus()
```

### Enable Audio

```javascript
// After user click
debug.audio.enableAudio()
```

### Reload Configuration

```javascript
await debug.notification.reloadConfig()
```

## Troubleshooting

### Audio Not Playing

1. Ensure user has clicked to enable audio
2. Check volume: `debug.audio.getStatus()`
3. Verify audio file paths
4. Check browser console for errors

### Notifications Not Showing

1. Check queue: `debug.notification.queue.getStatus()`
2. Verify Phoenix connection
3. Check configuration exists for event type
4. Ensure queue isn't paused

### Performance Issues

1. Check animation frame rate
2. Monitor memory: `debug.system.getMemoryUsage()`
3. Verify GSAP cleanup
4. Check for memory leaks in console

## Development Guidelines

### Code Style

- Use SolidJS signals for reactive state
- Follow existing GSAP patterns
- Maintain type safety with TypeScript
- Use path aliases (@/, ~/, +/)

### Testing

- Write tests for new features
- Use Bun test framework
- Mock Phoenix channels properly
- Test audio preloading

### Performance

- Limit queue to 50 notifications
- Use GSAP contexts for cleanup
- Preload audio with pools
- Monitor memory usage

## Contributing

1. Read the [main CLAUDE.md](../../CLAUDE.md)
2. Follow established patterns
3. Write tests for new features
4. Update documentation
5. Run pre-commit validation

## License

Part of the Landale streaming system.
