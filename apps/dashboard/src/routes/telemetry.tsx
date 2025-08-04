/**
 * Telemetry Route
 *
 * Full telemetry dashboard view for the pop-out window.
 * Uses the centralized telemetry service for real-time data.
 */

import { createFileRoute } from '@tanstack/solid-router'
import { Show, For, onMount, createEffect, onCleanup } from 'solid-js'
import { TelemetryServiceProvider, useTelemetryService } from '@/services/telemetry-service'
import { useStreamService } from '@/services/stream-service'

export const Route = createFileRoute('/telemetry')({
  component: () => (
    <TelemetryServiceProvider>
      <TelemetryPage />
    </TelemetryServiceProvider>
  )
})

function TelemetryPage() {
  const { websocketStats, performanceMetrics, systemInfo, serviceMetrics, requestRefresh } = useTelemetryService()
  const { connectionState } = useStreamService()

  let intervalId: number

  onMount(() => {
    requestRefresh()

    // Refresh every 2 seconds
    intervalId = setInterval(() => {
      requestRefresh()
    }, 2000)
  })

  onCleanup(() => {
    if (intervalId) clearInterval(intervalId)
  })

  const formatUptime = (seconds: number | undefined) => {
    if (!seconds) return 'N/A'
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    return `${hours}h ${minutes}m`
  }

  return (
    <div class="min-h-screen bg-black text-gray-100">
      {/* Header */}
      <div class="border-b border-gray-800 bg-gray-950/50 backdrop-blur">
        <div class="flex items-center justify-between px-6 py-3">
          <div class="flex items-center gap-4">
            <h1 class="text-lg font-medium">Telemetry</h1>
            <div class="flex items-center gap-2 text-xs text-gray-500">
              <span>Phoenix WebSocket</span>
              <div
                class={`h-1.5 w-1.5 rounded-full ${connectionState() === 'connected' ? 'bg-green-500' : 'bg-red-500'}`}
              />
            </div>
          </div>
          <div class="text-xs text-gray-500">{new Date().toLocaleTimeString()}</div>
        </div>
      </div>

      {/* Stats Grid */}
      <div class="grid grid-cols-4 gap-px bg-gray-800 p-px">
        {/* System Status */}
        <div class="bg-gray-950 p-4">
          <div class="mb-2 text-xs font-medium text-gray-400">System</div>
          <div class="space-y-2">
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Status</span>
              <span
                class={`text-sm font-medium ${
                  systemInfo()?.status === 'healthy'
                    ? 'text-green-400'
                    : systemInfo()?.status === 'degraded'
                      ? 'text-yellow-400'
                      : 'text-red-400'
                }`}>
                {systemInfo()?.status || 'Unknown'}
              </span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Uptime</span>
              <span class="font-mono text-sm text-gray-300">{formatUptime(systemInfo()?.uptime)}</span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Version</span>
              <span class="font-mono text-sm text-gray-300">{systemInfo()?.version || 'N/A'}</span>
            </div>
          </div>
        </div>

        {/* WebSocket Stats */}
        <div class="bg-gray-950 p-4">
          <div class="mb-2 text-xs font-medium text-gray-400">Connections</div>
          <div class="space-y-2">
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Active</span>
              <span class="text-2xl font-bold text-blue-400">{websocketStats()?.total_connections || 0}</span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Channels</span>
              <span class="font-mono text-sm text-gray-300">{websocketStats()?.active_channels || 0}</span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Disconnects</span>
              <span class="font-mono text-sm text-gray-300">{websocketStats()?.recent_disconnects || 0}</span>
            </div>
          </div>
        </div>

        {/* Memory Stats */}
        <div class="bg-gray-950 p-4">
          <div class="mb-2 text-xs font-medium text-gray-400">Memory</div>
          <div class="space-y-2">
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Total</span>
              <span class="text-2xl font-bold text-purple-400">
                {Math.round(performanceMetrics()?.memory?.total_mb || 0)}
                <span class="text-xs font-normal text-gray-500">MB</span>
              </span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Processes</span>
              <span class="font-mono text-sm text-gray-300">
                {Math.round(performanceMetrics()?.memory?.processes_mb || 0)}MB
              </span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Binary</span>
              <span class="font-mono text-sm text-gray-300">
                {Math.round(performanceMetrics()?.memory?.binary_mb || 0)}MB
              </span>
            </div>
          </div>
        </div>

        {/* CPU Stats */}
        <div class="bg-gray-950 p-4">
          <div class="mb-2 text-xs font-medium text-gray-400">Processing</div>
          <div class="space-y-2">
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Schedulers</span>
              <span class="text-2xl font-bold text-green-400">{performanceMetrics()?.cpu?.schedulers || 0}</span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Run Queue</span>
              <span class="font-mono text-sm text-gray-300">{performanceMetrics()?.cpu?.run_queue || 0}</span>
            </div>
            <div class="flex items-baseline justify-between">
              <span class="text-xs text-gray-500">Avg Duration</span>
              <span class="font-mono text-sm text-gray-300">
                {Math.round(websocketStats()?.average_connection_duration || 0)}ms
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Detailed Sections */}
      <div class="grid grid-cols-2 gap-px bg-gray-800 p-px">
        {/* Channel Distribution */}
        <div class="bg-gray-950 p-4">
          <h3 class="mb-3 text-xs font-medium text-gray-400">Active Channels by Type</h3>
          <Show
            when={websocketStats()?.channels_by_type}
            fallback={<div class="text-xs text-gray-600">No active channels</div>}>
            <div class="space-y-1">
              <For each={Object.entries(websocketStats()?.channels_by_type || {})}>
                {([type, count]) => (
                  <div class="flex items-center justify-between rounded bg-gray-900 px-3 py-2">
                    <span class="text-xs text-gray-400">{type}</span>
                    <span class="font-mono text-sm font-medium text-gray-200">{count as number}</span>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </div>

        {/* Message Queues */}
        <div class="bg-gray-950 p-4">
          <h3 class="mb-3 text-xs font-medium text-gray-400">Message Queues</h3>
          <Show
            when={performanceMetrics()?.message_queue}
            fallback={<div class="text-xs text-gray-600">No queue data</div>}>
            <div class="space-y-1">
              <For each={Object.entries(performanceMetrics()?.message_queue || {})}>
                {([service, count]) => (
                  <div class="flex items-center justify-between rounded bg-gray-900 px-3 py-2">
                    <span class="text-xs text-gray-400">{service}</span>
                    <span class="font-mono text-sm font-medium text-gray-200">{count as number}</span>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </div>
      </div>

      {/* Service Status */}
      <Show when={serviceMetrics()}>
        <div class="border-t border-gray-800 bg-gray-950/50 px-6 py-4">
          <h3 class="mb-3 text-xs font-medium text-gray-400">Service Status</h3>
          <div class="grid grid-cols-4 gap-4">
            {/* Phononmaser */}
            <div class="rounded bg-gray-900 p-3">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-xs font-medium text-gray-400">Phononmaser</span>
                <div
                  class={`h-2 w-2 rounded-full ${
                    serviceMetrics()?.phononmaser?.connected ? 'bg-green-500' : 'bg-red-500'
                  }`}
                />
              </div>
              <Show
                when={serviceMetrics()?.phononmaser?.connected}
                fallback={
                  <div class="text-xs text-red-400">{serviceMetrics()?.phononmaser?.error || 'Disconnected'}</div>
                }>
                <div class="space-y-1">
                  <div class="text-xs text-gray-500">
                    Status: <span class="text-gray-300">{serviceMetrics()?.phononmaser?.status}</span>
                  </div>
                  <div class="text-xs text-gray-500">
                    WS: <span class="text-gray-300">{serviceMetrics()?.phononmaser?.websocket_state}</span>
                  </div>
                </div>
              </Show>
            </div>

            {/* Seed */}
            <div class="rounded bg-gray-900 p-3">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-xs font-medium text-gray-400">Seed</span>
                <div
                  class={`h-2 w-2 rounded-full ${serviceMetrics()?.seed?.connected ? 'bg-green-500' : 'bg-red-500'}`}
                />
              </div>
              <Show
                when={serviceMetrics()?.seed?.connected}
                fallback={<div class="text-xs text-red-400">{serviceMetrics()?.seed?.error || 'Disconnected'}</div>}>
                <div class="space-y-1">
                  <div class="text-xs text-gray-500">
                    Status: <span class="text-gray-300">{serviceMetrics()?.seed?.status}</span>
                  </div>
                  <div class="text-xs text-gray-500">
                    WS: <span class="text-gray-300">{serviceMetrics()?.seed?.websocket_state}</span>
                  </div>
                </div>
              </Show>
            </div>

            {/* OBS */}
            <div class="rounded bg-gray-900 p-3">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-xs font-medium text-gray-400">OBS</span>
                <div
                  class={`h-2 w-2 rounded-full ${serviceMetrics()?.obs?.connected ? 'bg-green-500' : 'bg-red-500'}`}
                />
              </div>
              <Show
                when={serviceMetrics()?.obs?.connected}
                fallback={<div class="text-xs text-red-400">{serviceMetrics()?.obs?.error || 'Disconnected'}</div>}>
                <div class="text-xs text-gray-500">
                  Status: <span class="text-gray-300">{serviceMetrics()?.obs?.status || 'healthy'}</span>
                </div>
              </Show>
            </div>

            {/* Twitch */}
            <div class="rounded bg-gray-900 p-3">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-xs font-medium text-gray-400">Twitch</span>
                <div
                  class={`h-2 w-2 rounded-full ${serviceMetrics()?.twitch?.connected ? 'bg-green-500' : 'bg-red-500'}`}
                />
              </div>
              <Show
                when={serviceMetrics()?.twitch?.connected}
                fallback={<div class="text-xs text-red-400">{serviceMetrics()?.twitch?.error || 'Disconnected'}</div>}>
                <div class="text-xs text-gray-500">
                  Status: <span class="text-gray-300">{serviceMetrics()?.twitch?.status || 'healthy'}</span>
                </div>
              </Show>
            </div>
          </div>
        </div>
      </Show>

      {/* Lifetime Totals */}
      <Show when={websocketStats()?.totals}>
        <div class="border-t border-gray-800 bg-gray-950/50 px-6 py-4">
          <h3 class="mb-3 text-xs font-medium text-gray-400">Lifetime Totals</h3>
          <div class="grid grid-cols-4 gap-4">
            <div>
              <div class="text-xs text-gray-500">Total Connects</div>
              <div class="text-xl font-bold text-gray-200">{websocketStats()?.totals?.connects || 0}</div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Total Disconnects</div>
              <div class="text-xl font-bold text-gray-200">{websocketStats()?.totals?.disconnects || 0}</div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Channel Joins</div>
              <div class="text-xl font-bold text-gray-200">{websocketStats()?.totals?.joins || 0}</div>
            </div>
            <div>
              <div class="text-xs text-gray-500">Channel Leaves</div>
              <div class="text-xl font-bold text-gray-200">{websocketStats()?.totals?.leaves || 0}</div>
            </div>
          </div>
        </div>
      </Show>
    </div>
  )
}
