/**
 * Connection Telemetry Component
 *
 * Displays detailed WebSocket connection metrics and service health status.
 * Perfect for Dashboard visibility while keeping the Omnibar simple.
 */

import { createSignal, onCleanup, onMount, Show, For } from 'solid-js'
import { useStreamService } from '@/services/stream-service'

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

interface SystemHealth {
  status: 'healthy' | 'degraded' | 'unhealthy'
  timestamp: number
  services: Record<string, any>
  system?: {
    uptime: number
    version: string
    environment: string
  }
}

export function ConnectionTelemetry() {
  const { connectionState, getSocket } = useStreamService()

  const [serviceHealth, setServiceHealth] = createSignal<ServiceHealth[]>([])
  const [systemHealth, setSystemHealth] = createSignal<SystemHealth | null>(null)
  const [isExpanded, setIsExpanded] = createSignal(false)
  const [lastUpdate, setLastUpdate] = createSignal<number>(Date.now())

  let healthCheckInterval: number | undefined

  // Initialize service health from connection state
  const updateServiceHealth = () => {
    const services: ServiceHealth[] = []

    // WebSocket connection from our local state
    services.push({
      name: 'Phoenix WebSocket',
      connected: connectionState().connected,
      reconnectAttempts: connectionState().reconnectAttempts,
      lastHeartbeat: connectionState().lastHeartbeat,
      error: connectionState().error
    })

    setServiceHealth(services)
    setLastUpdate(Date.now())
  }

  // Subscribe to real-time health updates
  const subscribeToHealthUpdates = () => {
    return null
  }

  onMount(() => {
    // Initial fetch
    updateServiceHealth()

    // Subscribe to real-time updates
    const channel = subscribeToHealthUpdates()

    // Poll health endpoint every 30 seconds
    healthCheckInterval = window.setInterval(updateServiceHealth, 30000)

    onCleanup(() => {
      if (healthCheckInterval) {
        clearInterval(healthCheckInterval)
      }
      if (channel) {
        channel.leave()
      }
    })
  })

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)

    if (days > 0) return `${days}d ${hours}h`
    if (hours > 0) return `${hours}h ${minutes}m`
    return `${minutes}m`
  }

  const formatTimestamp = (timestamp?: number) => {
    if (!timestamp) return 'Never'
    const date = new Date(timestamp)
    return date.toLocaleTimeString()
  }

  const getStatusColor = (connected: boolean) => {
    return connected ? 'text-green-500' : 'text-red-500'
  }

  const getHealthIcon = (status?: string) => {
    switch (status) {
      case 'healthy':
        return '✓'
      case 'degraded':
        return '⚠'
      case 'unhealthy':
        return '✗'
      default:
        return '?'
    }
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900">
      <div class="flex items-center justify-between p-3">
        <h3 class="text-xs font-medium text-gray-300">Connection Status</h3>
        <button onClick={() => setIsExpanded(!isExpanded())} class="text-xs text-gray-500 hover:text-gray-300">
          {isExpanded() ? '−' : '+'}
        </button>
      </div>

      {/* Summary View */}
      <div class="px-3 pb-3 text-xs text-gray-500">
        <div class="flex justify-between py-0.5">
          <span>Status:</span>
          <span class={systemHealth()?.status === 'healthy' ? 'text-green-500' : 'text-yellow-500'}>
            {systemHealth()?.status || 'Unknown'}
          </span>
        </div>
        <div class="flex justify-between py-0.5">
          <span>Uptime:</span>
          <span>{systemHealth()?.system ? formatUptime(systemHealth()!.system.uptime) : 'N/A'}</span>
        </div>
      </div>

      {/* Service Status */}
      <div class="px-3 pb-3">
        <div class="text-xs text-gray-500">
          <For each={serviceHealth()}>
            {(service) => (
              <div class="flex items-center justify-between py-0.5">
                <div class="flex items-center gap-1.5">
                  <span class={getStatusColor(service.connected)}>{service.connected ? '●' : '○'}</span>
                  <span>{service.name}</span>
                </div>
                <Show when={service.error}>
                  <span class="text-red-500">{service.error}</span>
                </Show>
                <Show when={!service.error && service.connected && service.reconnectAttempts}>
                  <span class="text-gray-600">R:{service.reconnectAttempts}</span>
                </Show>
              </div>
            )}
          </For>
        </div>
      </div>

      {/* Expanded Details */}
      <Show when={isExpanded()}>
        <div class="border-t border-gray-800 px-3 pt-2 pb-3">
          <div class="space-y-1 text-xs text-gray-600">
            <div class="flex justify-between">
              <span>Connection:</span>
              <span class={getStatusColor(connectionState().connected)}>
                {connectionState().connected ? 'Connected' : 'Disconnected'}
              </span>
            </div>

            <Show when={connectionState().reconnectAttempts > 0}>
              <div class="flex justify-between">
                <span>Reconnects:</span>
                <span>{connectionState().reconnectAttempts}</span>
              </div>
            </Show>

            <Show when={connectionState().lastHeartbeat}>
              <div class="flex justify-between">
                <span>Last Heartbeat:</span>
                <span class="font-mono">{formatTimestamp(connectionState().lastHeartbeat)}</span>
              </div>
            </Show>

            <Show when={connectionState().lastConnected}>
              <div class="flex justify-between">
                <span>Connected:</span>
                <span class="font-mono">{formatTimestamp(connectionState().lastConnected)}</span>
              </div>
            </Show>

            <Show when={systemHealth()?.system}>
              <div class="mt-1 border-t border-gray-800 pt-1">
                <div class="flex justify-between">
                  <span>Environment:</span>
                  <span>{systemHealth()!.system!.environment}</span>
                </div>
                <div class="flex justify-between">
                  <span>Version:</span>
                  <span>{systemHealth()!.system!.version}</span>
                </div>
              </div>
            </Show>
          </div>
        </div>
      </Show>
    </div>
  )
}
