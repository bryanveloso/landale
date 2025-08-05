/**
 * Connection Health Indicator
 *
 * Shows Phoenix WebSocket connection status.
 * Only visible when debugging or when there are connection issues.
 */

import { Show, createMemo, createSignal, onMount, onCleanup } from 'solid-js'
import { Socket } from 'phoenix'
import { createPhoenixSocket, isSocketConnected } from '@landale/shared/phoenix-connection'

export const ConnectionIndicator = () => {
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  let checkInterval: ReturnType<typeof setInterval> | null = null

  onMount(() => {
    // Create a Phoenix socket
    const phoenixSocket = createPhoenixSocket()
    setSocket(phoenixSocket)

    // Check connection status periodically
    checkInterval = setInterval(() => {
      setIsConnected(isSocketConnected(phoenixSocket))
    }, 1000)
  })

  onCleanup(() => {
    if (checkInterval) {
      clearInterval(checkInterval)
    }
    const s = socket()
    if (s) {
      s.disconnect()
    }
  })

  // Show indicator if debugging or disconnected
  const shouldShow = createMemo(() => {
    const searchParams = new URLSearchParams(window.location.search)
    const debugMode = searchParams.get('debug') === 'true'
    return debugMode || !isConnected()
  })

  const statusColor = createMemo(() => {
    return isConnected() ? 'bg-green-500' : 'bg-red-500'
  })

  const statusText = createMemo(() => {
    return isConnected() ? 'Connected' : 'Disconnected'
  })

  return (
    <Show when={shouldShow()}>
      <div class="fixed right-4 bottom-4 z-50 flex items-center gap-2 rounded bg-gray-900/90 px-3 py-2 text-sm text-white backdrop-blur">
        <div class={`h-3 w-3 rounded-full ${statusColor()} animate-pulse`} />
        <span>Phoenix: {statusText()}</span>
      </div>
    </Show>
  )
}
