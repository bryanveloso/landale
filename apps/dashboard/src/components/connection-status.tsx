/**
 * Global Connection Status Component
 *
 * Single source of truth for WebSocket connection status.
 * Eliminates redundant status displays across components.
 */

import { useStreamService } from '@/services/stream-service'

export function ConnectionStatus() {
  const { connectionState, forceReconnect } = useStreamService()

  return (
    <div>
      <div>
        <span>{connectionState().connected ? 'Connected' : 'Disconnected'}</span>
        {!connectionState().connected && <button onClick={forceReconnect}>Retry</button>}
      </div>

      {connectionState().reconnectAttempts > 0 && <div>Reconnect attempts: {connectionState().reconnectAttempts}</div>}

      {connectionState().error && <div>{connectionState().error}</div>}

      {connectionState().lastConnected && (
        <div>Last connected: {new Date(connectionState().lastConnected!).toLocaleTimeString()}</div>
      )}
    </div>
  )
}
