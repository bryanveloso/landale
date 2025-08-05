/**
 * Telemetry Route
 *
 * Full telemetry dashboard view for the pop-out window.
 * Uses the centralized telemetry service for real-time data.
 */

import { createFileRoute } from '@tanstack/solid-router'
import { Show, For, onMount, onCleanup } from 'solid-js'
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

  let intervalId: number | undefined

  onMount(() => {
    requestRefresh()

    // Refresh every 2 seconds
    intervalId = window.setInterval(() => {
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
              <div class={`h-1.5 w-1.5 rounded-full ${connectionState().connected ? 'bg-green-500' : 'bg-red-500'}`} />
            </div>
          </div>
          <div class="text-xs text-gray-500">{new Date().toLocaleTimeString()}</div>
        </div>
      </div>

      {/* Connection Health Grid */}
      <div class="bg-gray-950 p-4">
        <h2 class="mb-4 text-sm font-medium text-gray-400">Connection Health</h2>
        <div class="grid grid-cols-2 gap-4">
          {/* WebSocket Connections */}
          <div class="space-y-3">
            <h3 class="text-xs font-medium tracking-wider text-gray-500 uppercase">WebSocket Status</h3>
            <Show
              when={websocketStats()?.channels_by_type}
              fallback={<div class="text-sm text-gray-600">No connection data</div>}>
              <For each={Object.entries(websocketStats()?.channels_by_type || {})}>
                {([type, count]) => {
                  const isHealthy = (count as number) > 0
                  const hasDisconnects = type === 'overlay' && (websocketStats()?.recent_disconnects || 0) > 0

                  return (
                    <div class="flex items-center justify-between rounded-lg bg-gray-900 px-3 py-2">
                      <div class="flex items-center gap-2">
                        <div
                          class={`h-2 w-2 rounded-full ${
                            hasDisconnects ? 'animate-pulse bg-yellow-500' : isHealthy ? 'bg-green-500' : 'bg-gray-600'
                          }`}
                        />
                        <span class="text-sm text-gray-300 capitalize">{type}</span>
                      </div>
                      <div class="flex items-center gap-2">
                        <Show when={hasDisconnects}>
                          <span class="text-xs text-yellow-400">{websocketStats()?.recent_disconnects} failures</span>
                        </Show>
                        <span class="font-mono text-sm font-medium text-gray-400">{count as number}</span>
                      </div>
                    </div>
                  )
                }}
              </For>
            </Show>

            {/* Overall health indicator */}
            <div class="mt-2 rounded-lg bg-gray-900 p-3">
              <div class="flex items-center justify-between">
                <span
                  class="text-xs text-gray-500"
                  title="Ratio of successful connections to total connection attempts. Low values in development are normal due to hot-reload.">
                  Connection Stability
                </span>
                <Show when={websocketStats()?.totals} fallback={<span class="text-sm text-gray-600">No data</span>}>
                  {() => {
                    const total = websocketStats()?.totals?.connects || 0
                    const disconnects = websocketStats()?.totals?.disconnects || 0
                    const rate = total > 0 ? ((total - disconnects) / total) * 100 : 100

                    return (
                      <div class="flex items-center gap-2">
                        <span
                          class={`text-sm font-medium ${
                            rate >= 99 ? 'text-green-400' : rate >= 95 ? 'text-yellow-400' : 'text-red-400'
                          }`}>
                          {rate.toFixed(1)}%
                        </span>
                        <Show when={rate < 50}>
                          <span class="text-xs text-gray-500">(Dev environment)</span>
                        </Show>
                      </div>
                    )
                  }}
                </Show>
              </div>
            </div>
          </div>

          {/* System Stats */}
          <div class="space-y-3">
            <h3 class="text-xs font-medium tracking-wider text-gray-500 uppercase">System Health</h3>

            <div class="rounded-lg bg-gray-900 p-3">
              <div class="mb-2 flex items-center justify-between">
                <span class="text-sm text-gray-300">Phoenix Server</span>
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
              <div class="text-xs text-gray-500">Uptime: {formatUptime(systemInfo()?.uptime)}</div>
            </div>

            <div class="rounded-lg bg-gray-900 p-3">
              <div class="flex items-center justify-between">
                <span class="text-sm text-gray-300">Active Connections</span>
                <span class="text-xl font-bold text-blue-400">{websocketStats()?.total_connections || 0}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Performance & Resource Status */}
      <div class="mt-px bg-gray-950 p-4">
        <h2 class="mb-4 text-sm font-medium text-gray-400">System Resources</h2>
        <div class="grid grid-cols-3 gap-4">
          {/* Memory Status */}
          <div class="rounded-lg bg-gray-900 p-3">
            <div class="mb-2 flex items-center justify-between">
              <span class="text-xs text-gray-500">Memory Usage</span>
              <Show when={performanceMetrics()?.memory}>
                {() => {
                  const total = performanceMetrics()?.memory?.total_mb || 0
                  const percent = total > 1000 ? (total / 4096) * 100 : (total / 1024) * 100
                  return (
                    <span
                      class={`text-xs font-medium ${
                        percent > 80 ? 'text-red-400' : percent > 60 ? 'text-yellow-400' : 'text-green-400'
                      }`}>
                      {percent.toFixed(0)}%
                    </span>
                  )
                }}
              </Show>
            </div>
            <div class="text-xl font-bold text-purple-400">
              {Math.round(performanceMetrics()?.memory?.total_mb || 0)}
              <span class="text-xs font-normal text-gray-500"> MB</span>
            </div>
          </div>

          {/* CPU Status */}
          <div class="rounded-lg bg-gray-900 p-3">
            <div class="mb-2 flex items-center justify-between">
              <span class="text-xs text-gray-500">Run Queue</span>
              <Show when={performanceMetrics()?.cpu}>
                {() => {
                  const queue = performanceMetrics()?.cpu?.run_queue || 0
                  return (
                    <span
                      class={`text-xs font-medium ${
                        queue > 10 ? 'text-red-400' : queue > 5 ? 'text-yellow-400' : 'text-green-400'
                      }`}>
                      {queue === 0 ? 'Idle' : 'Active'}
                    </span>
                  )
                }}
              </Show>
            </div>
            <div class="text-xl font-bold text-green-400">
              {performanceMetrics()?.cpu?.run_queue || 0}
              <span class="text-xs font-normal text-gray-500"> tasks</span>
            </div>
          </div>

          {/* Connection Duration */}
          <div class="rounded-lg bg-gray-900 p-3">
            <div class="mb-2 text-xs text-gray-500">Avg Connection</div>
            <div class="text-xl font-bold text-blue-400">
              {(() => {
                const ms = websocketStats()?.average_connection_duration || 0
                if (ms < 1000) return `${Math.round(ms)} ms`
                if (ms < 60000) return `${(ms / 1000).toFixed(1)} s`
                return `${(ms / 60000).toFixed(1)} m`
              })()}
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
