# Dashboard Debug Commands

## WebSocket Testing (Browser Console)

### Check Connection Status

```javascript
// Check if socket is connected
window.phoenixSocket.connectionState()

// Check layer state connection
window.isConnected()

// View current layer state
window.layerState()
```

### Test Channel Communication

```javascript
// Get the stream channel (if connected)
const channel = window.phoenixSocket.channels.find((c) => c.topic === 'stream:overlays')

// Request fresh state from server
channel.push('request_state', {})

// Test channel events (these are received automatically)
// - stream_state: Full state updates
// - show_changed: Show transitions
// - interrupt: Priority interrupts
// - content_update: Real-time content updates
```

### Test Layer State Transformation

```javascript
// View raw server state vs transformed client state
console.log('Server state:', window.phoenixSocket.channels.find((c) => c.topic === 'stream:overlays').state)
console.log('Client layer state:', window.layerState())
```

## Expected Behavior

1. **Socket Connection**: Should connect to `ws://localhost:7175/socket`
2. **Channel Join**: Should join `stream:overlays` channel
3. **Initial State**: Should receive initial state after join
4. **Layer Display**: Should show layer states (foreground/midground/background)
5. **Real-time Updates**: Should update when server state changes

## Common Issues

- **Connection Failed**: Check Phoenix server is running on port 7175
- **No Layer Data**: Check if StreamProducer is initialized
- **State Not Updating**: Check WebSocket connection and channel subscriptions
