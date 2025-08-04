/**
 * Connection Telemetry Component
 *
 * Displays detailed WebSocket connection metrics and service health status.
 * Perfect for Dashboard visibility while keeping the Omnibar simple.
 */

import { createSignal, onCleanup, onMount, Show } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import type { WebSocketStats, PerformanceMetrics, SystemInfo } from '@/types/telemetry'

interface ServiceHealth {
  name: string
  connected: boolean
  lastHeartbeat?: number
  reconnectAttempts?: number
  circuitBreakerTrips?: number
  heartbeatFailures?: number
  consecutiveFailures?: number
  error?: string
}

interface ConnectionTelemetryProps {
  websocketStats?: WebSocketStats | null
  performanceMetrics?: PerformanceMetrics | null
  systemInfo?: SystemInfo | null
}

export function ConnectionTelemetry(_props: ConnectionTelemetryProps) {
  const { connectionState } = useStreamService()

  const [_serviceHealth, setServiceHealth] = createSignal<ServiceHealth[]>([])

  let healthCheckInterval: number | undefined

  // Initialize service health from connection state
  const updateServiceHealth = () => {
    const services: ServiceHealth[] = []

    // WebSocket connection from our local state
    services.push({
      name: 'Phoenix WebSocket',
      connected: connectionState().connected,
      reconnectAttempts: connectionState().reconnectAttempts,
      error: connectionState().error || undefined
    })

    setServiceHealth(services)
  }

  onMount(() => {
    // Initial fetch
    updateServiceHealth()

    // Poll health endpoint every 30 seconds
    healthCheckInterval = window.setInterval(updateServiceHealth, 30000)

    onCleanup(() => {
      if (healthCheckInterval) {
        clearInterval(healthCheckInterval)
      }
    })
  })

  const formatTimestamp = (timestamp?: number) => {
    if (!timestamp) return 'Never'
    const date = new Date(timestamp)
    return date.toLocaleTimeString()
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <h3 class="mb-2 text-xs font-medium text-gray-300">Connection Status</h3>

      {/* Connection Status */}
      <div class="text-xs">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <span class={connectionState().connected ? 'text-green-500' : 'text-red-500'}>
              {connectionState().connected ? '●' : '○'}
            </span>
            <span class="text-gray-300">Phoenix WebSocket</span>
          </div>
          <Show when={connectionState().connected && connectionState().lastConnected}>
            <span class="text-gray-500">{formatTimestamp(new Date(connectionState().lastConnected!).getTime())}</span>
          </Show>
          <Show when={!connectionState().connected}>
            <span class="text-red-500">Disconnected</span>
          </Show>
        </div>

        <Show when={connectionState().reconnectAttempts > 0}>
          <div class="mt-1 pl-5 text-gray-600">
            {connectionState().reconnectAttempts} reconnect{connectionState().reconnectAttempts === 1 ? '' : 's'}
          </div>
        </Show>

        <Show when={connectionState().error}>
          <div class="mt-1 pl-5 text-xs text-red-500">{connectionState().error}</div>
        </Show>
      </div>
    </div>
  )
}
