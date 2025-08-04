/**
 * Connection Status Component for Status Bar
 */

import { useStreamService } from '@/services/stream-service'

export function ConnectionStatus() {
  const { connectionState } = useStreamService()

  return <div>{connectionState().connected ? 'WebSocket: Connected' : 'WebSocket: Disconnected'}</div>
}
