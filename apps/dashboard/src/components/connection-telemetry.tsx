/**
 * Connection Telemetry Component
 *
 * Displays detailed WebSocket connection metrics and service health status.
 * Perfect for Dashboard visibility while keeping the Omnibar simple.
 */

import { createSignal, onCleanup, onMount, Show, For, createEffect } from 'solid-js'
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

interface ConnectionTelemetryProps {
  websocketStats?: WebSocketStats | null
  performanceMetrics?: PerformanceMetrics | null
  systemInfo?: SystemInfo | null
}

export function ConnectionTelemetry(props: ConnectionTelemetryProps) {
  const { connectionState, getSocket } = useStreamService()

  const [serviceHealth, setServiceHealth] = createSignal<ServiceHealth[]>([])
  const [systemHealth, setSystemHealth] = createSignal<SystemHealth | null>(null)
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

  const subscribeToHealthUpdates = () => {
    return null
  }

  onMount(() => {
    // Initial fetch
    updateServiceHealth()

    // Update system health from props when they change
    createEffect(() => {
      if (props.systemInfo) {
        setSystemHealth({
          status: props.systemInfo.status || 'unknown',
          timestamp: Date.now(),
          services: {},
          system: {
            uptime: props.systemInfo.uptime || 0,
            version: props.systemInfo.version || '0.1.0',
            environment: props.systemInfo.environment || 'production'
          }
        })
      }
    })

    // Poll health endpoint every 30 seconds
    healthCheckInterval = window.setInterval(updateServiceHealth, 30000)

    onCleanup(() => {
      if (healthCheckInterval) {
        clearInterval(healthCheckInterval)
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
            <span class="text-gray-500">{formatTimestamp(new Date(connectionState().lastConnected).getTime())}</span>
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
