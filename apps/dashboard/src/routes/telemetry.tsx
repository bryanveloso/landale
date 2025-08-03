/**
 * Telemetry Route
 *
 * Full telemetry dashboard view for the pop-out window.
 * This provides a more comprehensive view than the drawer.
 */

import { createFileRoute } from '@tanstack/solid-router'
import { ConnectionTelemetry } from '@/components/connection-telemetry'
import { createSignal, onMount, onCleanup } from 'solid-js'
import { useStreamService } from '@/services/stream-service'

export const Route = createFileRoute('/telemetry')({
  component: TelemetryPage
})

function TelemetryPage() {
  const { getSocket } = useStreamService()
  const [websocketStats, setWebsocketStats] = createSignal<any>(null)
  const [performanceMetrics, setPerformanceMetrics] = createSignal<any>(null)

  let telemetryChannel: any

  onMount(() => {
    const socket = getSocket()
    if (!socket) return

    // Subscribe to telemetry channel for detailed metrics
    telemetryChannel = socket.channel('dashboard:telemetry')

    telemetryChannel.on('telemetry_snapshot', (data: any) => {
      setWebsocketStats(data.websocket)
      setPerformanceMetrics(data.performance)
    })

    telemetryChannel.on('telemetry_update', (data: any) => {
      setWebsocketStats(data.websocket)
      setPerformanceMetrics(data.performance)
    })

    telemetryChannel.on('websocket_metrics', (data: any) => {
      setWebsocketStats(data)
    })

    telemetryChannel.on('performance_metrics', (data: any) => {
      setPerformanceMetrics(data)
    })

    telemetryChannel
      .join()
      .receive('ok', () => console.log('Joined telemetry channel'))
      .receive('error', (resp: any) => console.error('Failed to join telemetry channel:', resp))

    // Request initial telemetry data
    telemetryChannel.push('get_telemetry', {})
  })

  onCleanup(() => {
    if (telemetryChannel) {
      telemetryChannel.leave()
    }
  })

  return (
    <div class="min-h-screen bg-gray-900 text-white">
      {/* Header */}
      <div class="sticky top-0 z-10 border-b border-gray-700 bg-gray-800/50 backdrop-blur-sm">
        <div class="px-6 py-4">
          <h1 class="text-2xl font-bold">Landale System Telemetry</h1>
          <p class="mt-1 text-sm text-gray-400">Real-time monitoring and metrics</p>
        </div>
      </div>

      {/* Main Content */}
      <div class="space-y-6 p-6">
        {/* Connection Status */}
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <div>
            <h2 class="mb-4 text-lg font-semibold">Connection Status</h2>
            <ConnectionTelemetry />
          </div>

          {/* WebSocket Statistics */}
          <div class="rounded-lg bg-gray-800 p-6">
            <h2 class="mb-4 text-lg font-semibold">WebSocket Statistics</h2>
            {websocketStats() ? (
              <div class="space-y-3 text-sm">
                <div class="grid grid-cols-2 gap-2">
                  <span class="text-gray-400">Total Connections:</span>
                  <span class="font-mono">{websocketStats().total_connections || 0}</span>
                </div>
                <div class="grid grid-cols-2 gap-2">
                  <span class="text-gray-400">Active Channels:</span>
                  <span class="font-mono">{websocketStats().active_channels || 0}</span>
                </div>
                <div class="grid grid-cols-2 gap-2">
                  <span class="text-gray-400">Recent Disconnects:</span>
                  <span class="font-mono">{websocketStats().recent_disconnects || 0}</span>
                </div>
                <div class="grid grid-cols-2 gap-2">
                  <span class="text-gray-400">Avg Connection Duration:</span>
                  <span class="font-mono">{Math.round(websocketStats().average_connection_duration || 0)}ms</span>
                </div>

                {/* Channel breakdown */}
                {websocketStats().channels_by_type && (
                  <div class="mt-4 border-t border-gray-700 pt-4">
                    <h3 class="mb-2 text-sm font-medium">Active Channels by Type</h3>
                    {Object.entries(websocketStats().channels_by_type).map(([type, count]) => (
                      <div class="flex justify-between py-1">
                        <span class="text-gray-400">{type}:</span>
                        <span class="font-mono">{count as number}</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ) : (
              <p class="text-gray-500">Loading WebSocket statistics...</p>
            )}
          </div>
        </div>

        {/* Performance Metrics */}
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
          {/* Memory Usage */}
          <div class="rounded-lg bg-gray-800 p-6">
            <h3 class="mb-4 text-lg font-semibold">Memory Usage</h3>
            {performanceMetrics()?.memory ? (
              <div class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <span class="text-gray-400">Total:</span>
                  <span class="font-mono">{Math.round(performanceMetrics().memory.total_mb)}MB</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">Processes:</span>
                  <span class="font-mono">{Math.round(performanceMetrics().memory.processes_mb)}MB</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">Binary:</span>
                  <span class="font-mono">{Math.round(performanceMetrics().memory.binary_mb)}MB</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">ETS:</span>
                  <span class="font-mono">{Math.round(performanceMetrics().memory.ets_mb)}MB</span>
                </div>
              </div>
            ) : (
              <p class="text-sm text-gray-500">Loading memory metrics...</p>
            )}
          </div>

          {/* CPU Metrics */}
          <div class="rounded-lg bg-gray-800 p-6">
            <h3 class="mb-4 text-lg font-semibold">CPU Usage</h3>
            {performanceMetrics()?.cpu ? (
              <div class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <span class="text-gray-400">Schedulers:</span>
                  <span class="font-mono">{performanceMetrics().cpu.schedulers}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">Run Queue:</span>
                  <span class="font-mono">{performanceMetrics().cpu.run_queue}</span>
                </div>
              </div>
            ) : (
              <p class="text-sm text-gray-500">Loading CPU metrics...</p>
            )}
          </div>

          {/* Message Queues */}
          <div class="rounded-lg bg-gray-800 p-6">
            <h3 class="mb-4 text-lg font-semibold">Message Queues</h3>
            {performanceMetrics()?.message_queue ? (
              <div class="space-y-2 text-sm">
                {Object.entries(performanceMetrics().message_queue).map(([service, count]) => (
                  <div class="flex justify-between">
                    <span class="text-gray-400">{service}:</span>
                    <span class="font-mono">{count as number}</span>
                  </div>
                ))}
              </div>
            ) : (
              <p class="text-sm text-gray-500">Loading queue metrics...</p>
            )}
          </div>
        </div>

        {/* Telemetry Totals */}
        {websocketStats()?.totals && (
          <div class="rounded-lg bg-gray-800 p-6">
            <h3 class="mb-4 text-lg font-semibold">Lifetime Totals</h3>
            <div class="grid grid-cols-2 gap-4 text-sm lg:grid-cols-4">
              <div>
                <span class="block text-gray-400">Total Connects</span>
                <span class="font-mono text-2xl">{websocketStats().totals.connects}</span>
              </div>
              <div>
                <span class="block text-gray-400">Total Disconnects</span>
                <span class="font-mono text-2xl">{websocketStats().totals.disconnects}</span>
              </div>
              <div>
                <span class="block text-gray-400">Total Joins</span>
                <span class="font-mono text-2xl">{websocketStats().totals.joins}</span>
              </div>
              <div>
                <span class="block text-gray-400">Total Leaves</span>
                <span class="font-mono text-2xl">{websocketStats().totals.leaves}</span>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
