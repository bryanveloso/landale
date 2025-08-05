/**
 * Telemetry Route
 *
 * Simple service status view.
 * Uses direct Phoenix connections without telemetry wrapper.
 */

import { createFileRoute } from '@tanstack/solid-router'
import { Show, onMount, onCleanup } from 'solid-js'
import { TelemetryServiceProvider, useTelemetryService } from '@/services/telemetry-service'
import { usePhoenixService } from '@/services/phoenix-service'

export const Route = createFileRoute('/telemetry')({
  component: () => (
    <TelemetryServiceProvider>
      <TelemetryPage />
    </TelemetryServiceProvider>
  )
})

function TelemetryPage() {
  const { serviceMetrics, systemInfo, requestRefresh } = useTelemetryService()
  const { isConnected } = usePhoenixService()

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
            <h1 class="text-lg font-medium">Service Status</h1>
            <div class="flex items-center gap-2 text-xs text-gray-500">
              <span>Phoenix</span>
              <div class={`h-1.5 w-1.5 rounded-full ${isConnected() ? 'bg-green-500' : 'bg-red-500'}`} />
            </div>
          </div>
          <div class="text-xs text-gray-500">{new Date().toLocaleTimeString()}</div>
        </div>
      </div>

      {/* System Status */}
      <div class="bg-gray-950 p-4">
        <h2 class="mb-4 text-sm font-medium text-gray-400">System Health</h2>
        <div class="grid grid-cols-2 gap-4">
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
              <span class="text-sm text-gray-300">Connection Status</span>
              <span class={`text-sm font-medium ${isConnected() ? 'text-green-400' : 'text-red-400'}`}>
                {isConnected() ? 'Connected' : 'Disconnected'}
              </span>
            </div>
          </div>
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
    </div>
  )
}
