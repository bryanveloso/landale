import { createSignal, Show, onMount, onCleanup } from 'solid-js'
import type { Component } from 'solid-js'
import { Channel } from 'phoenix'
import { usePhoenixService } from '@/services/phoenix-service'

interface ServiceControlsProps {
  serviceMetrics: () => Record<string, unknown>
  requestRefresh: () => void
}

export const ServiceControls: Component<ServiceControlsProps> = (props) => {
  const { socket } = usePhoenixService()
  const [servicesChannel, setServicesChannel] = createSignal<Channel | null>(null)
  const [loading, setLoading] = createSignal<Map<string, string>>(new Map())

  const isLoading = (service: string, action?: string) => {
    const loadingAction = loading().get(service)
    return action ? loadingAction === action : !!loadingAction
  }

  const setServiceLoading = (service: string, action: string | null) => {
    setLoading((prev) => {
      const newMap = new Map(prev)
      if (action) {
        newMap.set(service, action)
      } else {
        newMap.delete(service)
      }
      return newMap
    })
  }

  const performAction = async (service: string, action: 'start' | 'stop' | 'restart') => {
    const channel = servicesChannel()
    if (!channel) return

    setServiceLoading(service, action)

    try {
      await new Promise((resolve, reject) => {
        channel
          .push(action, { service })
          .receive('ok', (response: unknown) => {
            resolve(response)
          })
          .receive('error', (error: Record<string, unknown>) => {
            // Extract error message from Phoenix response
            const errorMessage = error?.reason || error?.message || error?.error || 'Unknown error'
            reject(new Error(String(errorMessage)))
          })
          .receive('timeout', () => reject(new Error('Request timeout')))
      })

      // Refresh telemetry after action
      setTimeout(() => {
        props.requestRefresh()
        setServiceLoading(service, null)
      }, 1500)
    } catch {
      setServiceLoading(service, null)
      // Could show error in UI here if needed
    }
  }

  onMount(() => {
    const phoenixSocket = socket()
    if (!phoenixSocket) return

    const channel = phoenixSocket.channel('dashboard:services')

    channel
      .join()
      .receive('ok', () => {
        setServicesChannel(channel)
      })
      .receive('error', ({ reason: _reason }) => {
        // Channel join failed - services may not be available
      })

    // Listen for service events
    channel.on('service_starting', ({ service: _service }) => {
      setTimeout(() => props.requestRefresh(), 500)
    })
    channel.on('service_stopping', ({ service: _service }) => {
      setTimeout(() => props.requestRefresh(), 500)
    })
    channel.on('service_restarting', ({ service: _service }) => {
      setTimeout(() => props.requestRefresh(), 500)
    })
  })

  onCleanup(() => {
    const channel = servicesChannel()
    if (channel) {
      channel.leave()
      setServicesChannel(null)
    }
  })

  const renderServiceRow = (serviceName: string, displayName: string) => {
    const metrics = props.serviceMetrics()
    const serviceData = metrics?.[serviceName]
    const isConnected = serviceData?.connected
    const error = serviceData?.error

    return (
      <div class="space-y-1.5">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <div class={`h-2 w-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
            <span class="text-gray-400">{displayName}</span>
          </div>
          <Show when={isConnected} fallback={<span class="text-red-400">{error || 'Disconnected'}</span>}>
            <span class="text-green-400">Connected</span>
          </Show>
        </div>

        {/* Control buttons for Phononmaser and Seed only */}
        <Show when={serviceName === 'phononmaser' || serviceName === 'seed'}>
          <div class="ml-4 flex gap-1">
            <button
              onClick={() => performAction(serviceName, 'start')}
              disabled={isConnected || isLoading(serviceName)}
              class="rounded px-2 py-0.5 text-[10px] font-medium transition-colors hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
              classList={{
                'bg-gray-800 text-gray-300': !isConnected && !isLoading(serviceName),
                'bg-gray-700': isLoading(serviceName, 'start')
              }}>
              {isLoading(serviceName, 'start') ? 'Starting...' : 'Start'}
            </button>

            <button
              onClick={() => performAction(serviceName, 'stop')}
              disabled={!isConnected || isLoading(serviceName)}
              class="rounded px-2 py-0.5 text-[10px] font-medium transition-colors hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50"
              classList={{
                'bg-gray-800 text-gray-300': isConnected && !isLoading(serviceName),
                'bg-gray-700': isLoading(serviceName, 'stop')
              }}>
              {isLoading(serviceName, 'stop') ? 'Stopping...' : 'Stop'}
            </button>

            <button
              onClick={() => performAction(serviceName, 'restart')}
              disabled={isLoading(serviceName)}
              class="rounded bg-gray-800 px-2 py-0.5 text-[10px] font-medium text-gray-300 transition-colors hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
              classList={{
                'bg-gray-700': isLoading(serviceName, 'restart')
              }}>
              {isLoading(serviceName, 'restart') ? 'Restarting...' : 'Restart'}
            </button>
          </div>
        </Show>
      </div>
    )
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <div class="mb-2 flex items-center justify-between">
        <h3 class="text-xs font-medium text-gray-300">Service Status</h3>
        <Show when={servicesChannel()}>
          <span class="text-[10px] text-gray-500">via Nurvus</span>
        </Show>
      </div>
      <div class="space-y-3 text-xs">
        {renderServiceRow('phononmaser', 'Phononmaser')}
        {renderServiceRow('seed', 'Seed')}
        {renderServiceRow('obs', 'OBS')}
        {renderServiceRow('twitch', 'Twitch')}
      </div>
    </div>
  )
}
