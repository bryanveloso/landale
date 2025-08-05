/**
 * Connection Telemetry Component
 *
 * Displays detailed WebSocket connection metrics and service health status.
 * Perfect for Dashboard visibility while keeping the Omnibar simple.
 */

import { createSignal, onCleanup, onMount, Show } from 'solid-js'
import { usePhoenixService } from '@/services/phoenix-service'

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
  // Placeholder for future props
  className?: string
}

export function ConnectionTelemetry(_props: ConnectionTelemetryProps) {
  const { isConnected } = usePhoenixService()

  const [, setServiceHealth] = createSignal<ServiceHealth[]>([])

  let healthCheckInterval: number | undefined

  // Initialize service health from connection state
  const updateServiceHealth = () => {
    const services: ServiceHealth[] = []

    // WebSocket connection from our local state
    services.push({
      name: 'Phoenix WebSocket',
      connected: isConnected()
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

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <h3 class="mb-2 text-xs font-medium text-gray-300">Connection Status</h3>

      {/* Connection Status */}
      <div class="text-xs">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <span class={isConnected() ? 'text-green-500' : 'text-red-500'}>{isConnected() ? '●' : '○'}</span>
            <span class="text-gray-300">Phoenix WebSocket</span>
          </div>
          <Show when={!isConnected()}>
            <span class="text-red-500">Disconnected</span>
          </Show>
        </div>
      </div>
    </div>
  )
}
