# Omnibar Implementation Guide

This guide covers the infrastructure and patterns for implementing the omnibar revival. The server handles coordination, priority, and data aggregation. Your SolidJS implementation handles all visual presentation.

## Architecture Overview

```
Twitch EventSub → StreamProducer → StreamChannel → SolidJS Omnibar
     ↓              ↓                ↓              ↓
 Game Changes    Priority         WebSocket      Visual Display
                Management      Broadcasting
```

## Server Infrastructure

### StreamProducer (GenServer)

- **Priority System**: Alert (100) > Sub Train (50) > Ticker (10)
- **Show Detection**: Automatic via Twitch game changes
- **Content Rotation**: 15-second ticker intervals
- **Interrupt Management**: Timers, stacking, expiration

### StreamChannel (Phoenix Channel)

- **Topic**: `stream:overlays`
- **Real-time Events**: State updates, show changes, content updates
- **Reconnection**: Automatic with exponential backoff

## Data Structures

### StreamState

```typescript
interface StreamState {
  current_show: 'ironmon' | 'variety' | 'coding'
  active_content: {
    type: string
    data: any
    priority: number
    duration?: number
    started_at: string
  } | null
  priority_level: 'alert' | 'sub_train' | 'ticker'
  interrupt_stack: Array<{
    type: string
    priority: number
    id: string
    started_at: string
    duration?: number
  }>
  ticker_rotation: string[]
  metadata: {
    last_updated: string
    state_version: number
  }
}
```

### Content Types

#### Emote Stats (`emote_stats`)

```typescript
{
  type: 'emote_stats',
  data: {
    emotes: {
      'pepePls': 847,
      '5Head': 203,
      'OMEGALUL': 156
    },
    native_emotes: {
      'avalonPls': 42,
      'avalonLove': 28
    }
  }
}
```

#### Sub Train (`sub_train`)

```typescript
{
  type: 'sub_train',
  data: {
    count: 5,
    latest_subscriber: 'username',
    latest_tier: '1000',
    total_months: 36
  }
}
```

#### Alert (`alert`)

```typescript
{
  type: 'alert',
  data: {
    message: 'RAID INCOMING!',
    level: 'critical'
  }
}
```

#### IronMON Stats (`ironmon_run_stats`)

```typescript
{
  type: 'ironmon_run_stats',
  data: {
    run_number: 47,
    deaths: 3,
    location: 'Cerulean City',
    gym_progress: 2
  }
}
```

## SolidJS Integration Patterns

### 1. Using the Hook

```typescript
import { useStreamChannel } from '../hooks/useStreamChannel'

function Omnibar() {
  const { streamState, isConnected } = useStreamChannel()

  // streamState() is reactive - updates automatically
  // isConnected() shows WebSocket status
}
```

### 2. Show-based Theming

```typescript
const getThemeClass = () => {
  const show = streamState().current_show
  return `theme-${show}` // theme-ironmon, theme-variety, theme-coding
}
```

### 3. Priority-based Styling

```typescript
const getPriorityClass = () => {
  const priority = streamState().priority_level
  return `priority-${priority}` // priority-alert, priority-sub_train, priority-ticker
}
```

### 4. Content Switching

```typescript
const renderContent = () => {
  const content = streamState().active_content
  if (!content) return null

  switch (content.type) {
    case 'emote_stats':
      return <EmoteStats data={content.data} />
    case 'sub_train':
      return <SubTrain data={content.data} />
    // ... etc
  }
}
```

### 5. Real-time Updates

The hook automatically handles:

- WebSocket reconnection
- State synchronization
- Real-time content updates
- Connection status monitoring

## CSS Targeting

Use data attributes for styling:

```css
/* Main container */
[data-omnibar] {
}

/* Show contexts */
[data-omnibar][data-show='ironmon'] {
}
[data-omnibar][data-show='variety'] {
}
[data-omnibar][data-show='coding'] {
}

/* Priority levels */
[data-omnibar][data-priority='alert'] {
}
[data-omnibar][data-priority='sub_train'] {
}
[data-omnibar][data-priority='ticker'] {
}

/* Connection status */
[data-omnibar][data-connected='false'] {
}

/* Content types */
[data-content='emote-stats'] {
}
[data-content='sub-train'] {
}
[data-content='alert'] {
}

/* Specific elements */
[data-emote-name] {
}
[data-emote-count] {
}
[data-train-count] {
}
[data-alert-message] {
}
```

## Animation Patterns

### Enter/Exit Animations

```typescript
const [animationState, setAnimationState] = createSignal<'enter' | 'exit' | 'idle'>('idle')

createEffect(() => {
  const hasContent = streamState().active_content !== null

  if (hasContent && !isVisible()) {
    setAnimationState('enter')
    setIsVisible(true)
  } else if (!hasContent && isVisible()) {
    setAnimationState('exit')
    setTimeout(() => setIsVisible(false), 300) // Match animation duration
  }
})
```

### Priority-based Animations

```css
[data-priority='alert'] {
  animation: alertPulse 1s ease-in-out infinite;
}

[data-priority='sub_train'] {
  animation: subTrainGlow 2s ease-in-out infinite alternate;
}
```

## Development Tools

### Debug Mode

```typescript
{import.meta.env.DEV && (
  <div data-omnibar-debug>
    <div>Show: {streamState().current_show}</div>
    <div>Priority: {streamState().priority_level}</div>
    <div>Connected: {isConnected() ? '✓' : '✗'}</div>
    <div>Content: {streamState().active_content?.type || 'none'}</div>
  </div>
)}
```

### Manual Testing

```typescript
// In dev console - trigger manual events
Server.StreamProducer.add_interrupt(:alert, %{message: "Test Alert"}, [duration: 5000])
Server.StreamProducer.change_show(:ironmon, %{game: %{name: "Pokemon FireRed"}})
```

## Server API

### Manual Controls (for dashboard)

```elixir
# Trigger alert
Server.StreamProducer.add_interrupt(:alert, %{message: "Breaking News!"}, [duration: 10_000])

# Force content display
Server.StreamProducer.force_content(:emote_stats, %{}, 30_000)

# Change show manually
Server.StreamProducer.change_show(:ironmon, %{game: %{name: "Pokemon FireRed"}})
```

### Content Aggregation

The server automatically aggregates:

- Real-time emote counts from chat events
- Sub train tracking with 5-minute timers
- Follow counts and recent followers
- IronMON stats from TCP integration

## Show Contexts

### IronMON Show

- **Game**: Pokemon FireRed/LeafGreen (category_id: "490100")
- **Content**: `[:ironmon_run_stats, :ironmon_deaths, :emote_stats, :recent_follows]`
- **Theme**: Electric/energetic (suggested: yellows, oranges)

### Variety Show

- **Game**: Just Chatting or unknown games
- **Content**: `[:emote_stats, :recent_follows, :stream_goals, :daily_stats]`
- **Theme**: Your classic brand colors

### Coding Show

- **Game**: Software and Game Development (category_id: "509658")
- **Content**: `[:emote_stats, :recent_follows]`
- **Theme**: Terminal/developer aesthetic (suggested: greens, monospace)

## Best Practices

1. **Use data attributes** for CSS targeting, not classes
2. **Keep animations smooth** - 60fps, hardware acceleration
3. **Handle connection loss** gracefully with visual indicators
4. **Test with mock data** during development
5. **Respect the priority system** - alerts always win
6. **Keep content readable** at streaming resolution
7. **Consider OBS integration** - transparent backgrounds, proper sizing

## Implementation Tips

- Start with one content type (emote_stats is good)
- Use CSS transforms for smooth animations
- Test WebSocket reconnection scenarios
- Consider mobile/responsive overlays
- Debug with real Twitch events in dev
- Use semantic color systems for show themes
- Keep text legible at 1080p streaming resolution
