# Routes vs Components Decision Framework

## Overview

This framework helps you decide when to create a new route (OBS browser source) versus when to create a component within an existing route.

## The Route Decision Tree

```
Does this feature need...
├── Independent positioning in OBS? → Route
├── Different z-index layering? → Route
├── Separate audio management? → Route
├── Different update frequencies? → Route
├── Isolation from other features? → Route
└── Otherwise → Component
```

## Route Criteria (Create New Browser Source)

### 1. **Independent Positioning**

Create a route when you need to position the feature independently in OBS scenes.

**Examples:**

- Webcam overlay (positioned over camera)
- Chat overlay (positioned in specific corner)
- Music display (positioned independently)

```typescript
// routes/music-display.tsx - Independent positioning
export function MusicDisplay() {
  return (
    <div class="music-container">
      <RainwaveWidget />
    </div>
  )
}
```

### 2. **Layer Management**

Create a route when you need different z-index behavior in OBS.

**Examples:**

- Alert system (always on top)
- Background animations (always behind)
- Takeover screens (full-screen overlay)

```typescript
// routes/base.tsx - Always on top layer
export function BaseLayer() {
  return (
    <div class="alert-layer">
      <AlertQueue />
      <EmergencyOverrides />
    </div>
  )
}
```

### 3. **Audio Isolation**

Create a route when audio needs to be managed separately.

**Examples:**

- Alert sounds (managed by base layer only)
- Music player (separate audio stream)
- TTS announcements (independent volume control)

```typescript
// routes/base.tsx - Handles all alert audio
function BaseLayer() {
  const playAlertSound = (type: string) => {
    // Only this route plays alert sounds
    audioManager.play(`/sounds/alerts/${type}.mp3`)
  }

  return <AlertSystem onAlert={playAlertSound} />
}
```

### 4. **Update Frequency Isolation**

Create a route when update frequencies differ significantly.

**Examples:**

- Real-time game stats (60fps updates)
- Periodic social stats (updates every few seconds)
- Static overlays (rarely change)

```typescript
// routes/shows/ironmon/realtime.tsx - High-frequency updates
export function RealtimeStats() {
  const { gameStats } = useIronmonTCP() // 60fps updates

  return (
    <div class="realtime-overlay">
      <HealthBar current={gameStats.hp} max={gameStats.maxHp} />
      <LocationDisplay location={gameStats.location} />
    </div>
  )
}
```

### 5. **Feature Isolation**

Create a route when you want complete independence from other systems.

**Examples:**

- Emote rain (full-screen particle system)
- Stream goals (completely separate from other features)
- Custom game integrations (isolated data sources)

## Component Criteria (Add to Existing Route)

### 1. **Shared Layout Context**

Create a component when it's part of a larger layout composition.

```typescript
// components/widgets/StreamStats.tsx
export function StreamStats() {
  return (
    <div class="stats-grid">
      <FollowerCount />
      <ViewerCount />
      <UptimeDisplay />
    </div>
  )
}

// Used in routes/shows/variety/main.tsx
function VarietyMain() {
  return (
    <div class="variety-layout">
      <StreamStats />  {/* Part of larger layout */}
      <RecentActivity />
      <StreamGoals />
    </div>
  )
}
```

### 2. **Shared Data Context**

Create a component when it uses the same data source as other components.

```typescript
// All use the same stream data
function ShowMain() {
  const { streamState } = useStreamChannel()

  return (
    <div>
      <ActiveContent content={streamState.active_content} />
      <InterruptQueue queue={streamState.interrupt_stack} />
      <ShowIndicator show={streamState.current_show} />
    </div>
  )
}
```

### 3. **Coordinated Animations**

Create a component when animations need to coordinate with other elements.

```typescript
// components/widgets/AlertDisplay.tsx
export function AlertDisplay({ alert }: { alert: Alert }) {
  const { showLayer, hideLayer } = useLayerOrchestrator()

  // Coordinates with other layer animations
  useEffect(() => {
    showLayer('foreground', alert)
    return () => hideLayer('foreground')
  })

  return <div class="alert-content">{alert.message}</div>
}
```

## Common Scenarios & Decisions

### Scenario 1: New Show Type

**Question**: Adding FFXIV overlay
**Decision**: Route (`/shows/ffxiv/main.tsx`)
**Reasoning**: Needs independent positioning, different layout, show-specific styling

### Scenario 2: Subscriber Goal Widget

**Question**: Adding subscriber progress bar
**Decision**: Component (`<SubscriberGoal />`)
**Reasoning**: Part of larger layout, shares stream data, coordinates with other widgets

### Scenario 3: Chat Integration

**Question**: Adding chat messages overlay
**Decision**: Route (`/chat-overlay.tsx`)
**Reasoning**: Needs independent positioning, different update frequency, isolated feature

### Scenario 4: Death Counter (IronMON)

**Question**: Adding death counter for IronMON
**Decision**: Component (`<DeathCounter />` in IronMON main)
**Reasoning**: IronMON-specific, part of game stats layout, shares game data

### Scenario 5: Emergency Alerts

**Question**: Adding emergency alert system
**Decision**: Route (`/base.tsx` - add to existing)
**Reasoning**: Needs audio control, always on top, but base layer already handles this

### Scenario 6: Emote Rain

**Question**: Adding full-screen emote particle effects
**Decision**: Route (`/emote-rain.tsx`)
**Reasoning**: Full-screen, independent positioning, separate from all other features

### Scenario 7: Build Status (Coding Show)

**Question**: Adding CI/CD build status
**Decision**: Component (`<BuildStatus />` in coding main)
**Reasoning**: Coding-specific, part of development stats layout

## File Organization Examples

### Route Structure

```
routes/
├── base.tsx                 # Universal alerts & audio
├── omnibar.tsx             # Priority messaging
├── takeover.tsx            # Full-screen interrupts
├── emote-rain.tsx          # Particle effects
├── chat-overlay.tsx        # Chat integration
├── music-display.tsx       # Rainwave widget
└── shows/
    ├── variety/
    │   └── main.tsx        # Variety show layout
    ├── coding/
    │   ├── main.tsx        # Development layout
    │   └── realtime.tsx    # Live coding stats
    └── ironmon/
        ├── main.tsx        # IronMON layout
        └── debug.tsx       # Debug overlay
```

### Component Usage

```typescript
// routes/shows/ironmon/main.tsx
function IronmonMain() {
  return (
    <div class="ironmon-layout">
      <RunStats />           {/* IronMON-specific component */}
      <DeathCounter />       {/* IronMON-specific component */}
      <LocationTracker />    {/* IronMON-specific component */}
      <StreamStats />        {/* Shared component */}
    </div>
  )
}

// routes/shows/variety/main.tsx
function VarietyMain() {
  return (
    <div class="variety-layout">
      <StreamStats />        {/* Same shared component */}
      <RecentActivity />     {/* Shared component */}
      <StreamGoals />        {/* Variety-specific component */}
    </div>
  )
}
```

## Anti-Patterns to Avoid

### ❌ Don't: Create Routes for Simple UI Variations

```typescript
// Bad - separate routes for color differences
routes/alerts-red.tsx
routes/alerts-blue.tsx

// Good - one route with styling variations
routes/base.tsx + CSS themes
```

### ❌ Don't: Create Components for Independent Features

```typescript
// Bad - emote rain as component limits positioning
<EmoteRain /> // in main layout

// Good - emote rain as independent route
routes/emote-rain.tsx
```

### ❌ Don't: Mix Audio Management Across Routes

```typescript
// Bad - multiple routes playing sounds
routes / alerts.tsx // plays alert sounds
routes / chat.tsx // plays notification sounds

// Good - centralized audio management
routes / base.tsx // handles all audio
```

## Quick Reference

| Feature Type    | Route | Component | Reason                  |
| --------------- | ----- | --------- | ----------------------- |
| Alert System    | ✅    | ❌        | Audio + layering        |
| Show Layout     | ✅    | ❌        | Independent positioning |
| Emote Rain      | ✅    | ❌        | Full-screen isolation   |
| Stats Widget    | ❌    | ✅        | Part of larger layout   |
| Recent Follows  | ❌    | ✅        | Shared data context     |
| Music Player    | ✅    | ❌        | Independent + audio     |
| Death Counter   | ❌    | ✅        | Show-specific widget    |
| Takeover Screen | ✅    | ❌        | Full-screen isolation   |

This framework helps maintain clean separation between OBS browser sources while keeping related functionality organized within appropriate routes.
