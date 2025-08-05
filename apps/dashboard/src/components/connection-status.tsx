/**
 * Connection Status Component for Status Bar
 */

import { usePhoenixService } from '@/services/phoenix-service'

export function ConnectionStatus() {
  const { isConnected } = usePhoenixService()

  return <div>{isConnected() ? 'WebSocket: Connected' : 'WebSocket: Disconnected'}</div>
}
