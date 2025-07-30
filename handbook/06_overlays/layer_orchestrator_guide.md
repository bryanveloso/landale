# Layer Orchestrator Usage Guide

## Overview

The Layer Orchestrator is a sophisticated system for managing streaming overlay content across three priority layers with smooth GSAP-powered animations. It handles content interruption, layer stacking, and automatic restoration for professional streaming presentations.

## Core Concept

The orchestrator manages three priority layers that work together to display streaming content without conflicts:

- **Foreground** (Priority 100): Critical alerts that must be seen immediately
- **Midground** (Priority 50): Celebrations and important notifications
- **Background** (Priority 10): Ambient stats and persistent information

## Architecture Overview

### Core Files

```
src/
├── hooks/use-layer-orchestrator.tsx    # Main orchestration logic
├── components/animated-layer.tsx       # Layer registration wrapper
├── components/layer-renderer.tsx       # Content type rendering
└── components/omnibar.tsx             # Integration example
```

> **Note**: Layer mappings are now provided by the server via the `layer` field in events. The frontend no longer maintains its own mapping configuration.

## How It Works

### 1. Layer State Management

Each layer has these states managed by the orchestrator:

```typescript
type LayerState = 'hidden' | 'entering' | 'active' | 'interrupted' | 'exiting'
```

**State Flow:**

- `hidden` → `entering` → `active` (normal flow)
- `active` → `interrupted` (when higher priority content appears)
- `interrupted` → `active` (when interruption ends)
- `active` → `exiting` → `hidden` (when content ends)

### 2. Content Interruption System

When higher priority content appears:

```typescript
// Foreground interrupts midground and background
// Midground interrupts background only
// Background never interrupts anything

const interruptionEffects = {
  midground: { y: 30, scale: 0.95, opacity: 0.7 },
  background: { y: 60, scale: 0.9, opacity: 0.5 }
}
```

### 3. Animation System

All transitions use GSAP timelines for smooth, professional animations:

```typescript
// Entry animation
gsap.fromTo(element, { y: 20, scale: 0.95, opacity: 0 }, { y: 0, scale: 1, opacity: 1, duration: 0.4 })

// Exit animation
gsap.to(element, { y: -20, scale: 0.95, opacity: 0, duration: 0.3 })
```

## Using the Layer Orchestrator

### Basic Hook Usage

```typescript
import { useLayerOrchestrator } from '@/hooks/use-layer-orchestrator'

function MyOverlayComponent() {
  const { showLayer, hideLayer, layerStates } = useLayerOrchestrator()

  // Show content on a specific layer
  const displayAlert = (alertData) => {
    showLayer('foreground', {
      type: 'alert',
      content: alertData,
      duration: 5000 // Auto-hide after 5 seconds
    })
  }

  // Hide content manually
  const clearAlert = () => {
    hideLayer('foreground')
  }

  return (
    <div>
      <AnimatedLayer priority="foreground" />
      <AnimatedLayer priority="midground" />
      <AnimatedLayer priority="background" />
    </div>
  )
}
```

### Integration with Stream Data

```typescript
// routes/omnibar.tsx
function Omnibar() {
  const { streamState } = useStreamChannel()
  const { showLayer, hideLayer } = useLayerOrchestrator()

  // Respond to stream events
  createEffect(() => {
    const content = streamState().active_content
    if (!content) return

    // Use server-provided layer information
    const layer = content.layer || 'background' // Server enriches events with layer
    showLayer(layer, content)
  })

  return (
    <div class="omnibar-container">
      <AnimatedLayer priority="foreground" />
      <AnimatedLayer priority="midground" />
      <AnimatedLayer priority="background" />
    </div>
  )
}
```

## Content Type Mapping

### Server-Side Layer Assignment

As of January 2025, layer mappings are centralized on the Phoenix server. Events broadcast from the server include a `layer` field that specifies which visual layer should display the content:

```typescript
// Events now include layer information
interface StreamContent {
  type: string
  data: unknown
  priority: number
  layer?: 'foreground' | 'midground' | 'background'  // Server-provided
}
```

### Show-Specific Behavior

The server determines layer assignments based on the current show context:

- **Ironmon**: Game-specific alerts (death_alert → foreground)
- **Variety**: Community focus (raid_alert → foreground, emote_stats → background)
- **Coding**: Development alerts (build_failure → foreground)

### Using Server-Provided Layers

```typescript
// Old way (removed):
// const layer = getLayerForContent(content.type, show)

// New way - use server-provided layer:
const layer = content.layer || 'background'
showLayer(layer, content)
```

## Advanced Usage Patterns

### 1. Auto-Hide with Duration

```typescript
showLayer('foreground', {
  type: 'raid_alert',
  content: raidData,
  duration: 8000 // Automatically hide after 8 seconds
})
```

### 2. Layer State Monitoring

```typescript
const { layerStates } = useLayerOrchestrator()

createEffect(() => {
  console.log('Foreground state:', layerStates().foreground.state)
  console.log('Current content:', layerStates().foreground.content)
})
```

### 3. Manual Layer Control

```typescript
const { showLayer, hideLayer, clearLayer } = useLayerOrchestrator()

// Show specific content
showLayer('midground', { type: 'sub_train', count: 5 })

// Hide current content
hideLayer('midground')

// Clear layer immediately (no animation)
clearLayer('background')
```

### 4. Layer Restoration

When higher priority content ends, interrupted layers automatically restore:

```typescript
// 1. Background shows stats
showLayer('background', statsContent)

// 2. Foreground shows alert (background gets interrupted)
showLayer('foreground', alertContent)

// 3. Alert ends (background automatically restores)
hideLayer('foreground') // Background content returns to active state
```

## Component Integration

### AnimatedLayer Component

The `AnimatedLayer` component handles layer registration and styling:

```typescript
<AnimatedLayer
  priority="foreground"
  contentType="alert"
  show="ironmon"
/>
```

**Props:**

- `priority`: Which layer this component represents
- `contentType`: Type of content for styling hooks (optional)
- `show`: Current show context for theming (optional)

### LayerRenderer Component

Renders different content types with appropriate markup:

```typescript
// Used internally by AnimatedLayer
<LayerRenderer
  content={content}
  show={currentShow}
/>
```

**Supported Content Types:**

- `alert` - Alert notifications
- `sub_train` - Subscriber celebrations
- `emote_stats` - Top emote displays
- `recent_follows` - Follower lists
- `ironmon_run_stats` - IronMON statistics
- And more...

## CSS Integration

### Data Attributes for Styling

Layers set data attributes for CSS targeting using Tailwind v4 best practices:

```css
/* Essential layer state styling in styles.css */
[data-state='entering'] {
  opacity: 0;
  transform: translateY(20px) scale(0.95);
}

[data-state='active'] {
  opacity: 1;
  transform: translateY(0) scale(1);
}

[data-state='interrupted'] {
  opacity: 0.7;
  transform: translateY(30px) scale(0.95);
}

[data-state='exiting'] {
  opacity: 0;
  transform: translateY(-20px) scale(0.95);
}

/* Priority-based z-index */
[data-priority='100'] {
  z-index: 100;
}
[data-priority='50'] {
  z-index: 50;
}
[data-priority='10'] {
  z-index: 10;
}

/* Content type specific styling */
[data-content-type='alert'] {
  background: var(--color-red-500/90);
  color: white;
  padding: var(--spacing-4);
  border-radius: var(--radius-lg);
}

[data-content-type='celebration'] {
  background: var(--color-purple-500/90);
  color: white;
  padding: var(--spacing-3);
  border-radius: var(--radius-md);
}

/* Show-specific theming using CSS custom properties */
[data-show='ironmon'] {
  --layer-accent: var(--color-red-500);
  --layer-bg: var(--color-red-500/10);
}

[data-show='variety'] {
  --layer-accent: var(--color-purple-500);
  --layer-bg: var(--color-purple-500/10);
}

[data-show='coding'] {
  --layer-accent: var(--color-green-500);
  --layer-bg: var(--color-green-500/10);
}
```

### Tailwind v4 Styling Best Practices

Following Tailwind v4 guidelines:

- **Use CSS custom properties** for dynamic theming values
- **No @apply directive** - Use utilities in components instead
- **Data attributes for state-based styling** - Perfect for layer orchestrator
- **Minimal CSS file** - Keep styles.css focused on essential selectors only

## Development and Debugging

### Debug Information

In development builds, the orchestrator provides debug information:

```typescript
{import.meta.env.DEV && (
  <div class="orchestrator-debug">
    <div>Foreground: {layerStates().foreground.state}</div>
    <div>Midground: {layerStates().midground.state}</div>
    <div>Background: {layerStates().background.state}</div>
  </div>
)}
```

### Performance Monitoring

The orchestrator includes built-in performance monitoring:

```typescript
const { showLayer } = useLayerOrchestrator()

// Automatically tracks animation performance
showLayer('foreground', content) // Logs animation timing in dev mode
```

## Best Practices

### 1. Content Priority Guidelines

**Use Foreground for:**

- Death alerts, critical failures
- Emergency announcements
- Full-screen takeovers
- Time-sensitive notifications

**Use Midground for:**

- Celebrations (subs, follows, cheers)
- Achievement notifications
- Level ups, badges, milestones
- Interactive elements

**Use Background for:**

- Persistent statistics
- Recent activity lists
- Stream goals progress
- Ambient information

### 2. Animation Timing

```typescript
// Good - reasonable durations
showLayer('foreground', content, { duration: 5000 })

// Avoid - too short for reading
showLayer('foreground', content, { duration: 1000 })

// Avoid - too long, blocks other content
showLayer('foreground', content, { duration: 30000 })
```

### 3. Content Lifecycle

```typescript
// Good - explicit content management
useEffect(() => {
  if (shouldShowAlert) {
    showLayer('foreground', alertContent)
  }

  return () => {
    hideLayer('foreground') // Clean up on unmount
  }
}, [shouldShowAlert])
```

### 4. Error Handling

```typescript
const { showLayer } = useLayerOrchestrator()

try {
  showLayer('foreground', content)
} catch (error) {
  console.error('Failed to show layer content:', error)
  // Fallback behavior
}
```

## Integration Examples

### Alert System Integration

```typescript
function AlertSystem() {
  const { showLayer } = useLayerOrchestrator()
  const { alerts } = useAlerts()

  createEffect(() => {
    const currentAlert = alerts().current
    if (currentAlert) {
      showLayer('foreground', {
        type: 'alert',
        message: currentAlert.message,
        severity: currentAlert.severity
      }, { duration: currentAlert.duration })
    }
  })

  return <AnimatedLayer priority="foreground" />
}
```

### Statistics Display Integration

```typescript
function StatsDisplay() {
  const { showLayer } = useLayerOrchestrator()
  const { stats } = useStreamStats()

  createEffect(() => {
    if (stats().shouldShow) {
      showLayer('background', {
        type: 'stream_stats',
        followers: stats().followers,
        viewers: stats().viewers,
        uptime: stats().uptime
      })
    }
  })

  return <AnimatedLayer priority="background" />
}
```

## OBS Browser Source Setup

### URL Configuration

```
Development: http://localhost:5173/omnibar
Production:  https://overlays.landale.dev/omnibar
```

### Browser Source Settings

```
Width: 1920
Height: 1080
FPS: 30 (60 for high-frequency content)
CSS: (empty - styling handled by components)
```

### Scene Layer Order

Position the omnibar browser source appropriately in your OBS scene:

```
Scene Layers (top to bottom):
1. Takeover Layer (emergency full-screen)
2. Omnibar (layer orchestrator)
3. Music Display
4. Webcam
5. Game Capture
```

This ensures the layer orchestrator can properly manage content priority without conflicts with other scene elements.

The Layer Orchestrator provides a robust foundation for professional streaming overlays with sophisticated content management, smooth animations, and OBS-optimized performance.
