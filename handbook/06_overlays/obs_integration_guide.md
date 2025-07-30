# OBS Integration Guide

## Overview

This guide explains how to organize and manage overlay browser sources in OBS Studio for optimal performance and maintainability.

## Browser Source Basics

### What is a Browser Source?

A browser source in OBS is a web browser that renders a specific URL directly into your scene. Each overlay route becomes a separate browser source.

### Standard Settings

- **Width**: 1920px
- **Height**: 1080px
- **FPS**: 30 (60 for high-frequency updates)
- **Custom CSS**: Use sparingly, prefer route-level styling

## Scene Organization Strategy

### Core Scene Structure

Every streaming scene should follow this layering pattern (top to bottom):

```
Scene: [Show Name]
├── 🚨 Takeover Layer         (/takeover)
├── 🔔 Universal Alerts       (/base)
├── 📱 Show-Specific Overlay  (/shows/{show}/main)
├── 🎵 Music Display         (/music-display)
├── 📹 Webcam
├── 🎮 Game Capture
└── 🖼️ Background
```

### Layer Order Importance

- **Higher in list = appears on top**
- **Takeover must be highest** (emergency full-screen)
- **Alerts above show content** (notifications priority)
- **Show content above game** (overlay information)

## Browser Source URLs

### Development URLs

```
Base Layer:           http://localhost:5173/base
Omnibar:             http://localhost:5173/omnibar
Takeover:            http://localhost:5173/takeover

Show Overlays:
Variety:             http://localhost:5173/shows/variety/main
Coding:              http://localhost:5173/shows/coding/main
IronMON:             http://localhost:5173/shows/ironmon/main

Standalone Features:
Emote Rain:          http://localhost:5173/emote-rain
Chat Overlay:        http://localhost:5173/chat-overlay
Music Display:       http://localhost:5173/music-display
```

### Production URLs

```
Base Layer:          https://overlays.landale.dev/base
Show Overlays:       https://overlays.landale.dev/shows/{show}/main
Features:            https://overlays.landale.dev/{feature}
```

## Scene Templates

### Basic Streaming Scene

```
Scene: Variety Stream
├── Takeover Layer    (/takeover)
├── Universal Alerts  (/base)
├── Variety Overlay   (/shows/variety/main)
├── Webcam
└── Game Capture
```

### Data-Dense Gaming Scene

```
Scene: IronMON Challenge
├── Takeover Layer     (/takeover)
├── Universal Alerts   (/base)
├── IronMON Overlay    (/shows/ironmon/main)
├── IronMON Realtime   (/shows/ironmon/realtime)
├── Music Display      (/music-display)
├── Webcam
└── Game Capture
```

### Development Stream Scene

```
Scene: Coding Stream
├── Takeover Layer    (/takeover)
├── Universal Alerts  (/base)
├── Coding Overlay    (/shows/coding/main)
├── Code Metrics      (/shows/coding/metrics)
├── Music Display     (/music-display)
├── Screen Capture
└── Webcam (small)
```

### Chat-Heavy Scene

```
Scene: Just Chatting
├── Takeover Layer    (/takeover)
├── Universal Alerts  (/base)
├── Variety Overlay   (/shows/variety/main)
├── Chat Overlay      (/chat-overlay)
├── Emote Rain        (/emote-rain)
└── Webcam (fullscreen)
```

## Audio Management Strategy

### Single Audio Source Rule

**Only the Base Layer (`/base`) should play audio** to prevent conflicts.

```typescript
// ✅ Good - Only base layer plays sounds
// routes/base.tsx
function BaseLayer() {
  const playAlertSound = (type: AlertType) => {
    audioManager.play(`/sounds/${type}.mp3`)
  }

  return <AlertSystem onAlert={playAlertSound} />
}

// ❌ Bad - Multiple routes playing audio
// routes/shows/ironmon/main.tsx - Don't do this!
function IronmonMain() {
  const playDeathSound = () => {
    audio.play('/sounds/death.mp3') // Conflicts with base layer
  }
}
```

### Audio File Organization

```
public/sounds/
├── alerts/
│   ├── follow.mp3
│   ├── subscribe.mp3
│   ├── donation.mp3
│   └── raid.mp3
├── celebrations/
│   ├── sub-train.mp3
│   ├── goal-reached.mp3
│   └── milestone.mp3
└── system/
    ├── error.mp3
    ├── success.mp3
    └── notification.mp3
```

## Performance Optimization

### Browser Source Settings

```
Width: 1920
Height: 1080
FPS: 30 (default) / 60 (high-frequency only)
Custom CSS: (leave empty - use route styling)
Shutdown source when not visible: ✅
Refresh browser when scene becomes active: ❌
```

### Memory Management

- **Limit active browser sources** (max 5-7 per scene)
- **Use scene collections** for different stream types
- **Refresh sources** if memory usage gets high
- **Close unused scenes** to free resources

### Update Frequency Guidelines

| Content Type     | FPS | Route Example             |
| ---------------- | --- | ------------------------- |
| Static overlays  | 30  | `/shows/variety/main`     |
| Real-time stats  | 60  | `/shows/ironmon/realtime` |
| Animations only  | 30  | `/base`                   |
| Particle effects | 60  | `/emote-rain`             |

## Browser Source Management

### Naming Conventions

Use descriptive names that match your route structure:

```
✅ Good Names:
- "Base - Universal Alerts"
- "IronMON - Main Overlay"
- "Variety - Stream Info"
- "Feature - Emote Rain"

❌ Bad Names:
- "Browser Source"
- "Overlay 1"
- "Web Page"
- "Thing"
```

### Source Organization in OBS

Group related sources using nested folders:

```
📁 Overlays/
  ├── 🚨 Base - Universal Alerts
  ├── 📱 IronMON - Main Overlay
  ├── 🎵 Music - Rainwave Display
  └── ✨ Effects - Emote Rain

📁 Cameras/
  ├── 📹 Main Webcam
  └── 📹 Overhead Cam

📁 Captures/
  ├── 🎮 Game Capture
  └── 🖥️ Desktop Capture
```

## Troubleshooting Common Issues

### Browser Source Not Loading

1. **Check URL**: Verify the route exists and is accessible
2. **Clear browser cache**: Right-click source → Properties → Refresh Cache
3. **Check console**: Open browser source properties → interact → F12 for errors
4. **Verify dimensions**: Ensure 1920x1080 matches your overlay design

### Audio Conflicts

1. **Multiple sources playing audio**: Only base layer should handle audio
2. **Echo/feedback**: Check that only one browser source has audio enabled
3. **No audio**: Verify base layer audio settings and file paths

### Performance Issues

1. **High CPU usage**: Reduce FPS on non-critical sources
2. **Memory leaks**: Refresh browser sources periodically
3. **Lag/stuttering**: Limit total number of active browser sources

### Animation Issues

1. **Animations not smooth**: Check FPS settings match animation requirements
2. **Animations cut off**: Verify overlay dimensions and positioning
3. **Timing issues**: Ensure proper cleanup in component `onCleanup`

## Scene Collection Strategy

### Create Different Collections for Stream Types

```
Collection: Variety Streaming
├── Scene: Starting Soon
├── Scene: Main Stream
├── Scene: Just Chatting
├── Scene: Break Screen
└── Scene: Ending Screen

Collection: IronMON Challenge
├── Scene: Challenge Setup
├── Scene: Active Run
├── Scene: Victory/Death
└── Scene: Run Review

Collection: Development
├── Scene: Code Review
├── Scene: Live Coding
├── Scene: Terminal Work
└── Scene: Demo/Testing
```

### Shared Sources Across Collections

Use **Add Existing** for sources that work across stream types:

- Base Layer (universal alerts)
- Music Display (consistent across shows)
- Webcam sources
- Background elements

## Quick Setup Checklist

### New Show Type Setup

1. **Create route**: `/shows/{show}/main.tsx`
2. **Add browser source**: URL, 1920x1080, 30fps
3. **Position in scene**: Above game capture, below alerts
4. **Test connectivity**: Verify WebSocket connection
5. **Configure styling**: Show-specific CSS variables
6. **Test animations**: Verify GSAP animations work
7. **Add to scene collections**: Include in relevant collections

### New Feature Setup

1. **Decide route vs component**: Use decision framework
2. **Create route if needed**: `/feature-name.tsx`
3. **Add browser source**: Appropriate dimensions and FPS
4. **Position correctly**: Based on feature requirements
5. **Test isolation**: Verify no conflicts with other sources
6. **Document usage**: Add to this guide

This guide ensures consistent, performant overlay management across all streaming scenarios.
