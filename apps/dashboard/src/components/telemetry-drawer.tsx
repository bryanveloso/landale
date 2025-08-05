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
  const { systemInfo, serviceMetrics, overlayHealth, requestRefresh } = useTelemetryService()

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
            <ConnectionTelemetry />

            {/* System Information */}
            <div class="space-y-px">
              <div class="border-b border-gray-800 bg-gray-900 p-3">
                <h3 class="mb-2 text-xs font-medium text-gray-300">System Information</h3>
                <div class="text-xs text-gray-500">
                  <Show when={systemInfo()} fallback={<span class="text-gray-600">Loading...</span>}>
                    <div class="flex justify-between py-0.5">
                      <span>Status:</span>
                      <span
                        class={`font-medium ${
                          systemInfo()?.status === 'healthy'
                            ? 'text-green-400'
                            : systemInfo()?.status === 'degraded'
                              ? 'text-yellow-400'
                              : 'text-red-400'
                        }`}>
                        {systemInfo()?.status || 'Unknown'}
                      </span>
                    </div>
                    <div class="flex justify-between py-0.5">
                      <span>Version:</span>
                      <span class="font-mono">{systemInfo()?.version || 'N/A'}</span>
                    </div>
                    <div class="flex justify-between py-0.5">
                      <span>Uptime:</span>
                      <span class="font-mono">
                        {(() => {
                          const seconds = systemInfo()?.uptime || 0
                          const hours = Math.floor(seconds / 3600)
                          const minutes = Math.floor((seconds % 3600) / 60)
                          return `${hours}h ${minutes}m`
                        })()}
                      </span>
                    </div>
                  </Show>
                </div>
              </div>

              {/* Service Status */}
              <Show when={serviceMetrics()}>
                <div class="border-b border-gray-800 bg-gray-900 p-3">
                  <h3 class="mb-2 text-xs font-medium text-gray-300">Service Status</h3>
                  <div class="space-y-2 text-xs">
                    {/* Phononmaser */}
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-2">
                        <div
                          class={`h-2 w-2 rounded-full ${serviceMetrics()?.phononmaser?.connected ? 'bg-green-500' : 'bg-red-500'}`}
                        />
                        <span class="text-gray-400">Phononmaser</span>
                      </div>
                      <Show
                        when={serviceMetrics()?.phononmaser?.connected}
                        fallback={
                          <span class="text-red-400">{serviceMetrics()?.phononmaser?.error || 'Disconnected'}</span>
                        }>
                        <span class="text-green-400">Connected</span>
                      </Show>
                    </div>

                    {/* Seed */}
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-2">
                        <div
                          class={`h-2 w-2 rounded-full ${serviceMetrics()?.seed?.connected ? 'bg-green-500' : 'bg-red-500'}`}
                        />
                        <span class="text-gray-400">Seed</span>
                      </div>
                      <Show
                        when={serviceMetrics()?.seed?.connected}
                        fallback={<span class="text-red-400">{serviceMetrics()?.seed?.error || 'Disconnected'}</span>}>
                        <span class="text-green-400">Connected</span>
                      </Show>
                    </div>

                    {/* OBS */}
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-2">
                        <div
                          class={`h-2 w-2 rounded-full ${serviceMetrics()?.obs?.connected ? 'bg-green-500' : 'bg-red-500'}`}
                        />
                        <span class="text-gray-400">OBS</span>
                      </div>
                      <Show
                        when={serviceMetrics()?.obs?.connected}
                        fallback={<span class="text-red-400">{serviceMetrics()?.obs?.error || 'Disconnected'}</span>}>
                        <span class="text-green-400">Connected</span>
                      </Show>
                    </div>

                    {/* Twitch */}
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-2">
                        <div
                          class={`h-2 w-2 rounded-full ${serviceMetrics()?.twitch?.connected ? 'bg-green-500' : 'bg-red-500'}`}
                        />
                        <span class="text-gray-400">Twitch</span>
                      </div>
                      <Show
                        when={serviceMetrics()?.twitch?.connected}
                        fallback={
                          <span class="text-red-400">{serviceMetrics()?.twitch?.error || 'Disconnected'}</span>
                        }>
                        <span class="text-green-400">Connected</span>
                      </Show>
                    </div>
                  </div>
                </div>
              </Show>

              {/* Overlay Health */}
              <Show when={overlayHealth() && overlayHealth()!.length > 0}>
                <div class="border-b border-gray-800 bg-gray-900 p-3">
                  <h3 class="mb-2 text-xs font-medium text-gray-300">Overlay Health</h3>
                  <div class="space-y-2 text-xs">
                    <For each={overlayHealth()}>
                      {(overlay) => (
                        <div class="flex items-center justify-between">
                          <div class="flex items-center gap-2">
                            <div class={`h-2 w-2 rounded-full ${overlay.connected ? 'bg-green-500' : 'bg-red-500'}`} />
                            <span class="text-gray-400">{overlay.name}</span>
                          </div>
                          <Show
                            when={overlay.connected}
                            fallback={<span class="text-red-400">{overlay.error || 'Disconnected'}</span>}>
                            <span class="text-green-400">
                              {overlay.channelState === 'joined' ? 'Connected' : overlay.channelState}
                            </span>
                          </Show>
                        </div>
                      )}
                    </For>
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
