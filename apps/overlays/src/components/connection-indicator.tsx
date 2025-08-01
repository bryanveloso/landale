/**
 * Connection Health Indicator
 *
 * Shows WebSocket connection status with resilience metrics.
 * Only visible when debugging or when there are connection issues.
 */

import { Show, createMemo } from 'solid-js'
import { useSocket } from '@/providers/socket-provider'
import { ConnectionState } from '@landale/shared/websocket'

export const ConnectionIndicator = () => {
  const { connectionState, healthMetrics, isConnected } = useSocket()

  // Show indicator if debugging or having issues
  const shouldShow = createMemo(() => {
    const searchParams = new URLSearchParams(window.location.search)
    const debugMode = searchParams.get('debug') === 'true'
    const metrics = healthMetrics()

    return (
      debugMode ||
      !isConnected() ||
      (metrics && (metrics.heartbeatFailures > 0 || metrics.isCircuitOpen || metrics.reconnectAttempts > 0))
    )
  })

  const statusColor = createMemo(() => {
    const state = connectionState()
    const metrics = healthMetrics()

    if (metrics?.isCircuitOpen) return 'bg-red-500'

    switch (state) {
      case ConnectionState.CONNECTED:
        return 'bg-green-500'
      case ConnectionState.CONNECTING:
      case ConnectionState.RECONNECTING:
        return 'bg-yellow-500'
      case ConnectionState.FAILED:
      case ConnectionState.DISCONNECTED:
        return 'bg-red-500'
      default:
        return 'bg-gray-500'
    }
  })

  const statusText = createMemo(() => {
    const state = connectionState()
    const metrics = healthMetrics()

    if (metrics?.isCircuitOpen) {
      return 'Circuit Breaker Open'
    }

    switch (state) {
      case ConnectionState.CONNECTED:
        return 'Connected'
      case ConnectionState.CONNECTING:
        return 'Connecting...'
      case ConnectionState.RECONNECTING:
        return `Reconnecting (${metrics?.reconnectAttempts ?? 0})`
      case ConnectionState.FAILED:
        return 'Connection Failed'
      case ConnectionState.DISCONNECTED:
        return 'Disconnected'
      default:
        return 'Unknown'
    }
  })

  return (
    <Show when={shouldShow()}>
      <div class="fixed right-4 bottom-4 z-50 rounded-lg bg-black/80 p-3 font-mono text-xs backdrop-blur-sm">
        <div class="mb-2 flex items-center gap-2">
          <div class={`h-2 w-2 rounded-full ${statusColor()} animate-pulse`} />
          <span class="text-white">{statusText()}</span>
        </div>

        <Show when={healthMetrics()}>
          {(metrics) => (
            <div class="space-y-1 text-gray-400">
              <Show when={metrics().totalReconnects > 0}>
                <div>Reconnects: {metrics().totalReconnects}</div>
              </Show>
              <Show when={metrics().heartbeatFailures > 0}>
                <div class="text-yellow-400">Heartbeat Failures: {metrics().heartbeatFailures}</div>
              </Show>
              <Show when={metrics().circuitBreakerTrips > 0}>
                <div class="text-red-400">Circuit Trips: {metrics().circuitBreakerTrips}</div>
              </Show>
              <Show when={metrics().failedReconnects > 0}>
                <div class="text-red-400">Failed Reconnects: {metrics().failedReconnects}</div>
              </Show>
            </div>
          )}
        </Show>
      </div>
    </Show>
  )
}
