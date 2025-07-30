# Omnibar Testing Guide

This guide helps you test the omnibar infrastructure and develop your styling.

## Quick Start

### 1. Start the Server

```bash
cd apps/server
mix phx.server
```

### 2. Start the Overlays

```bash
cd apps/overlays
bun dev
```

### 3. Open in Browser

- Overlays: http://localhost:5173
- Server API: http://localhost:4000

## Manual Testing Commands

Open the Elixir console:

```bash
cd apps/server
iex -S mix
```

### Trigger Different Content Types

```elixir
# Show emote stats
Server.StreamProducer.force_content(:emote_stats, %{}, 30_000)

# Show sub train
Server.StreamProducer.add_interrupt(:sub_train, %{
  count: 3,
  latest_subscriber: "testuser123",
  latest_tier: "1000"
}, [duration: 300_000])

# Trigger alert
Server.StreamProducer.add_interrupt(:alert, %{
  message: "RAID INCOMING!",
  level: "critical"
}, [duration: 10_000])

# Show recent follows
Server.StreamProducer.force_content(:recent_follows, %{}, 20_000)

# Show IronMON stats
Server.StreamProducer.force_content(:ironmon_run_stats, %{}, 25_000)
```

### Change Show Context

```elixir
# Switch to IronMON
Server.StreamProducer.change_show(:ironmon, %{
  game: %{id: "490100", name: "Pokemon FireRed"}
})

# Switch to variety
Server.StreamProducer.change_show(:variety, %{
  game: %{id: "509660", name: "Just Chatting"}
})

# Switch to coding
Server.StreamProducer.change_show(:coding, %{
  game: %{id: "509658", name: "Software and Game Development"}
})
```

### Simulate Real Events

```elixir
# Simulate chat messages with emotes
Server.ContentAggregator.record_emote_usage(
  ["pepePls", "5Head"],
  ["avalonPls"],
  "testuser"
)

# Simulate followers
Server.ContentAggregator.record_follower("newfollower123", System.system_time(:second))

# Check current state
Server.StreamProducer.get_current_state()
```

## Development Workflow

### 1. Test WebSocket Connection

```javascript
// In browser console
const ws = new WebSocket('ws://localhost:4000/socket/websocket')
ws.onopen = () => {
  ws.send(
    JSON.stringify({
      topic: 'stream:overlays',
      event: 'phx_join',
      payload: {},
      ref: '1'
    })
  )
}
ws.onmessage = (event) => console.log('Received:', JSON.parse(event.data))
```

### 2. Monitor State Changes

```elixir
# Subscribe to stream updates in IEx
Phoenix.PubSub.subscribe(Server.PubSub, "stream:updates")

# You'll see messages like:
# {:stream_update, %Server.StreamProducer{...}}
```

### 3. Debug Content Data

```elixir
# Check emote stats
Server.ContentAggregator.get_emote_stats()

# Check followers
Server.ContentAggregator.get_recent_followers(10)

# Check daily stats
Server.ContentAggregator.get_daily_stats()
```

## Mock Data Generator

Create some realistic test data:

```elixir
# Generate mock emote usage
emotes = ["pepePls", "5Head", "OMEGALUL", "Kappa", "LUL"]
native_emotes = ["avalonPls", "avalonLove", "avalonHype"]

for _ <- 1..100 do
  random_emotes = Enum.take_random(emotes, :rand.uniform(3))
  random_native = Enum.take_random(native_emotes, :rand.uniform(2))

  Server.ContentAggregator.record_emote_usage(
    random_emotes,
    random_native,
    "user#{:rand.uniform(50)}"
  )
end

# Generate mock followers
followers = ["alice", "bob", "charlie", "diana", "eve", "frank", "grace"]
for follower <- followers do
  Server.ContentAggregator.record_follower(follower, System.system_time(:second))
end
```

## Styling Development Tips

### 1. Use Data Attributes

```css
/* Target by show */
[data-omnibar][data-show='ironmon'] {
  /* IronMON theme */
}

[data-omnibar][data-show='variety'] {
  /* Variety theme */
}

/* Target by priority */
[data-omnibar][data-priority='alert'] {
  /* Alert styling */
}

/* Target by content type */
[data-content='emote-stats'] {
  /* Emote stats layout */
}
```

### 2. Animation Testing

```javascript
// Force quick content changes for animation testing
setInterval(() => {
  fetch('http://localhost:4000/api/test/force-content', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: ['emote_stats', 'recent_follows', 'alert'][Math.floor(Math.random() * 3)]
    })
  })
}, 5000)
```

### 3. Connection State Testing

```javascript
// Test disconnect/reconnect scenarios
ws.close() // Trigger reconnection logic
```

## Browser Source Setup (OBS)

### 1. Add Browser Source

- **URL**: `http://localhost:5173`
- **Width**: 1920
- **Height**: 1080
- **Custom CSS**: Add your overlay styles

### 2. Transparent Background

```css
body {
  background: transparent !important;
}
```

### 3. OBS Properties

- ✅ Shutdown source when not visible
- ✅ Refresh browser when scene becomes active
- ❌ Control audio via OBS (not needed)

## Common Issues

### WebSocket Connection

- **Port mismatch**: Ensure server on 4000, overlays on 5173
- **CORS issues**: Phoenix should handle this automatically
- **Firewall**: Check local firewall settings

### Content Not Showing

```elixir
# Check if StreamProducer is running
Process.whereis(Server.StreamProducer)

# Check current state
Server.StreamProducer.get_current_state()

# Check if events are being received
Phoenix.PubSub.subscribers(Server.PubSub, "stream:updates")
```

### Performance Issues

- Use CSS `transform` instead of position changes
- Enable hardware acceleration: `will-change: transform`
- Keep animations under 60fps
- Use `requestAnimationFrame` for smooth updates

## Production Checklist

- [ ] WebSocket reconnection works reliably
- [ ] All content types display correctly
- [ ] Show transitions are smooth
- [ ] Priority system works (alerts interrupt everything)
- [ ] Performance is smooth at 60fps
- [ ] Works in OBS browser source
- [ ] Mobile/responsive if needed
- [ ] Error states are handled gracefully
- [ ] Connection loss is indicated clearly
- [ ] Content loads within 2 seconds
