/**
 * Telemetry Drawer Component
 *
 * Provides quick access to telemetry metrics in a slide-out drawer.
 * Can be popped out to a separate window for detailed monitoring.
 */

import { Show, onMount, onCleanup, For, createEffect } from 'solid-js'
import { Portal } from 'solid-js/web'
import { invoke } from '@tauri-apps/api/core'
import { ConnectionTelemetry } from './connection-telemetry'
import { TelemetryServiceProvider, useTelemetryService } from '@/services/telemetry-service'

interface TelemetryDrawerProps {
  isOpen: boolean
  onClose: () => void
}

function TelemetryDrawerContent(props: TelemetryDrawerProps) {
  const { websocketStats, performanceMetrics, systemInfo, requestRefresh } = useTelemetryService()

  // Handle escape key to close
  const handleKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Escape' && props.isOpen) {
      props.onClose()
    }
  }

  // Refresh telemetry when drawer opens
  createEffect(() => {
    if (props.isOpen) {
      requestRefresh()
    }
  })

  onMount(() => {
    document.addEventListener('keydown', handleKeyDown)
  })

  onCleanup(() => {
    document.removeEventListener('keydown', handleKeyDown)
  })

  const handlePopOut = async () => {
    // Create new Tauri window for telemetry
    try {
      await invoke('create_telemetry_window')
      props.onClose() // Close drawer after popping out
    } catch (error) {
      console.error('Failed to create telemetry window:', error)
    }
  }

  const handleOverlayClick = () => {
    props.onClose()
  }

  const handleDrawerClick = (e: MouseEvent) => {
    e.stopPropagation() // Prevent closing when clicking inside drawer
  }

  return (
    <Portal>
      <Show when={props.isOpen}>
        {/* Overlay */}
        <div
          class="fixed inset-0 z-40 bg-black/50 transition-opacity duration-300"
          classList={{
            'opacity-0': !props.isOpen,
            'opacity-100': props.isOpen
          }}
          onClick={handleOverlayClick}
        />

        {/* Drawer */}
        <div
          class="fixed top-0 right-0 z-50 h-full w-[400px] transform border-l border-gray-800 bg-gray-950 shadow-2xl transition-transform duration-200 ease-out"
          classList={{
            'translate-x-0': props.isOpen,
            'translate-x-full': !props.isOpen
          }}
          onClick={handleDrawerClick}>
          {/* Header */}
          <div class="flex h-10 items-center justify-between border-b border-gray-800 bg-gray-900 px-3">
            <h2 class="text-xs font-medium text-gray-300">System Telemetry</h2>
            <div class="flex items-center gap-1">
              <button
                onClick={handlePopOut}
                class="rounded p-1 text-gray-400 transition-colors hover:bg-gray-800 hover:text-white"
                title="Pop out to separate window">
                <svg class="h-3.5 w-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                  />
                </svg>
              </button>
              <button
                onClick={props.onClose}
                class="rounded p-1 text-gray-400 transition-colors hover:bg-gray-800 hover:text-white"
                title="Close (Esc)">
                <svg class="h-3.5 w-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>

          {/* Content */}
          <div class="h-[calc(100%-40px)] overflow-y-auto bg-gray-950">
            <ConnectionTelemetry
              websocketStats={websocketStats()}
              performanceMetrics={performanceMetrics()}
              systemInfo={systemInfo()}
            />

            {/* Additional telemetry sections */}
            <div class="space-y-px">
              <div class="border-b border-gray-800 bg-gray-900 p-3">
                <h3 class="mb-2 text-xs font-medium text-gray-300">WebSocket Metrics</h3>
                <div class="text-xs text-gray-500">
                  <Show when={websocketStats()} fallback={<span class="text-gray-600">Loading...</span>}>
                    <div class="flex justify-between py-0.5">
                      <span>Connections:</span>
                      <span class="font-mono">{websocketStats()?.total_connections || 0}</span>
                    </div>
                    <div class="flex justify-between py-0.5">
                      <span>Active Channels:</span>
                      <span class="font-mono">{websocketStats()?.active_channels || 0}</span>
                    </div>
                    <div class="flex justify-between py-0.5">
                      <span>Recent Disconnects:</span>
                      <span class="font-mono">{websocketStats()?.recent_disconnects || 0}</span>
                    </div>
                    <Show when={websocketStats()?.channels_by_type}>
                      <div class="mt-1 border-t border-gray-800 pt-1">
                        <For each={Object.entries(websocketStats()?.channels_by_type || {})}>
                          {([type, count]) => (
                            <div class="flex justify-between py-0.5 pl-2">
                              <span>{type}:</span>
                              <span class="font-mono">{count as number}</span>
                            </div>
                          )}
                        </For>
                      </div>
                    </Show>
                  </Show>
                </div>
              </div>

              <div class="border-b border-gray-800 bg-gray-900 p-3">
                <h3 class="mb-2 text-xs font-medium text-gray-300">Performance</h3>
                <div class="text-xs text-gray-500">
                  <Show when={performanceMetrics()} fallback={<span class="text-gray-600">Loading...</span>}>
                    <Show when={performanceMetrics()?.memory}>
                      <div class="flex justify-between py-0.5">
                        <span>Memory:</span>
                        <span class="font-mono">{Math.round(performanceMetrics()?.memory?.total_mb || 0)} MB</span>
                      </div>
                      <div class="flex justify-between py-0.5">
                        <span>Processes:</span>
                        <span class="font-mono">{Math.round(performanceMetrics()?.memory?.processes_mb || 0)} MB</span>
                      </div>
                    </Show>
                    <Show when={performanceMetrics()?.cpu}>
                      <div class="flex justify-between py-0.5">
                        <span>Schedulers:</span>
                        <span class="font-mono">{performanceMetrics()?.cpu?.schedulers || 0}</span>
                      </div>
                      <div class="flex justify-between py-0.5">
                        <span>Run Queue:</span>
                        <span class="font-mono">{performanceMetrics()?.cpu?.run_queue || 0}</span>
                      </div>
                    </Show>
                  </Show>
                </div>
              </div>

              <Show when={websocketStats()?.totals}>
                <div class="border-b border-gray-800 bg-gray-900 p-3">
                  <h3 class="mb-2 text-xs font-medium text-gray-300">Lifetime Totals</h3>
                  <div class="text-xs text-gray-500">
                    <div class="flex justify-between py-0.5">
                      <span>Connects:</span>
                      <span class="font-mono">{websocketStats()?.totals?.connects || 0}</span>
                    </div>
                    <div class="flex justify-between py-0.5">
                      <span>Disconnects:</span>
                      <span class="font-mono">{websocketStats()?.totals?.disconnects || 0}</span>
                    </div>
                    <div class="flex justify-between py-0.5">
                      <span>Channel Joins:</span>
                      <span class="font-mono">{websocketStats()?.totals?.joins || 0}</span>
                    </div>
                    <div class="flex justify-between py-0.5">
                      <span>Channel Leaves:</span>
                      <span class="font-mono">{websocketStats()?.totals?.leaves || 0}</span>
                    </div>
                  </div>
                </div>
              </Show>
            </div>
          </div>
        </div>
      </Show>
    </Portal>
  )
}

export function TelemetryDrawer(props: TelemetryDrawerProps) {
  return (
    <TelemetryServiceProvider>
      <TelemetryDrawerContent {...props} />
    </TelemetryServiceProvider>
  )
}
