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
    const socket = getSocket()
    if (!socket) return

    const channel = socket.channel('dashboard:telemetry')

    channel.on('health_update', (data: any) => {
      if (data.services) {
        // Update service health from real-time events
        const services = serviceHealth()

        // Update or add service metrics
        Object.entries(data.services).forEach(([serviceName, metrics]: [string, any]) => {
          const existing = services.find((s) => s.name.toLowerCase() === serviceName.toLowerCase())
          if (existing) {
            Object.assign(existing, metrics)
          } else {
            services.push({
              name: serviceName,
              connected: metrics.connected || false,
              ...metrics
            })
          }
        })

        setServiceHealth([...services])
        setLastUpdate(Date.now())
      }
    })

    channel
      .join()
      .receive('ok', () => console.log('Joined telemetry channel'))
      .receive('error', (resp) => console.error('Failed to join telemetry channel:', resp))

    return channel
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
    <div class="rounded-lg bg-gray-800 p-4">
      <div class="mb-4 flex items-center justify-between">
        <h3 class="text-lg font-semibold">Connection Telemetry</h3>
        <button onClick={() => setIsExpanded(!isExpanded())} class="text-sm text-gray-400 hover:text-white">
          {isExpanded() ? 'Show Less' : 'Show More'}
        </button>
      </div>

      {/* Summary View */}
      <div class="mb-4 grid grid-cols-2 gap-4">
        <div>
          <span class="text-sm text-gray-400">System Status</span>
          <div class="flex items-center gap-2">
            <span class={systemHealth()?.status === 'healthy' ? 'text-green-500' : 'text-yellow-500'}>
              {getHealthIcon(systemHealth()?.status)} {systemHealth()?.status || 'Unknown'}
            </span>
          </div>
        </div>

        <div>
          <span class="text-sm text-gray-400">Uptime</span>
          <div>{systemHealth()?.system ? formatUptime(systemHealth()!.system.uptime) : 'N/A'}</div>
        </div>
      </div>

      {/* Service Status Grid */}
      <div class="space-y-2">
        <h4 class="text-sm font-medium text-gray-400">Services</h4>
        <div class="grid grid-cols-1 gap-2">
          <For each={serviceHealth()}>
            {(service) => (
              <div class="flex items-center justify-between rounded bg-gray-700 p-2">
                <div class="flex items-center gap-2">
                  <span class={getStatusColor(service.connected)}>{service.connected ? '●' : '○'}</span>
                  <span class="font-medium">{service.name}</span>
                </div>

                <Show when={service.error}>
                  <span class="text-xs text-red-400">{service.error}</span>
                </Show>

                <Show when={!service.error && service.connected && service.reconnectAttempts}>
                  <span class="text-xs text-gray-400">Reconnects: {service.reconnectAttempts}</span>
                </Show>
              </div>
            )}
          </For>
        </div>
      </div>

      {/* Expanded Telemetry Details */}
      <Show when={isExpanded()}>
        <div class="mt-4 border-t border-gray-700 pt-4">
          <h4 class="mb-2 text-sm font-medium text-gray-400">Detailed Metrics</h4>

          {/* WebSocket Metrics */}
          <div class="space-y-2 text-sm">
            <div class="grid grid-cols-2 gap-2">
              <span class="text-gray-400">Connection State:</span>
              <span class={getStatusColor(connectionState().connected)}>
                {connectionState().connected ? 'Connected' : 'Disconnected'}
              </span>
            </div>

            <Show when={connectionState().reconnectAttempts > 0}>
              <div class="grid grid-cols-2 gap-2">
                <span class="text-gray-400">Reconnect Attempts:</span>
                <span>{connectionState().reconnectAttempts}</span>
              </div>
            </Show>

            <Show when={connectionState().lastHeartbeat}>
              <div class="grid grid-cols-2 gap-2">
                <span class="text-gray-400">Last Heartbeat:</span>
                <span>{formatTimestamp(connectionState().lastHeartbeat)}</span>
              </div>
            </Show>

            <Show when={connectionState().lastConnected}>
              <div class="grid grid-cols-2 gap-2">
                <span class="text-gray-400">Last Connected:</span>
                <span>{formatTimestamp(connectionState().lastConnected)}</span>
              </div>
            </Show>

            {/* System Info */}
            <Show when={systemHealth()?.system}>
              <div class="mt-2 border-t border-gray-700 pt-2">
                <div class="grid grid-cols-2 gap-2">
                  <span class="text-gray-400">Environment:</span>
                  <span>{systemHealth()!.system!.environment}</span>
                </div>
                <div class="grid grid-cols-2 gap-2">
                  <span class="text-gray-400">Version:</span>
                  <span>{systemHealth()!.system!.version}</span>
                </div>
              </div>
            </Show>
          </div>

          {/* Last Update */}
          <div class="mt-4 text-xs text-gray-500">Last updated: {formatTimestamp(lastUpdate())}</div>
        </div>
      </Show>
    </div>
  )
}
