/**
 * Telemetry Service
 *
 * Centralized service for telemetry data management.
 * Handles Phoenix channel subscription and shares data between components.
 */

import { createContext, useContext, createSignal, onMount, onCleanup, createEffect } from 'solid-js'
import type { JSX } from 'solid-js'
import { Channel } from 'phoenix'
import { useStreamService } from './stream-service'
import type {
  WebSocketStats,
  PerformanceMetrics,
  SystemInfo,
  TelemetryResponse,
  TelemetrySnapshot
} from '@/types/telemetry'

interface TelemetryContextValue {
  websocketStats: () => WebSocketStats | null
  performanceMetrics: () => PerformanceMetrics | null
  systemInfo: () => SystemInfo | null
  isConnected: () => boolean
  requestRefresh: () => void
}

const TelemetryContext = createContext<TelemetryContextValue>()

export function useTelemetryService() {
  const context = useContext(TelemetryContext)
  if (!context) {
    throw new Error('useTelemetryService must be used within TelemetryServiceProvider')
  }
  return context
}

interface TelemetryServiceProviderProps {
  children: JSX.Element
}

export function TelemetryServiceProvider(props: TelemetryServiceProviderProps) {
  const { getSocket } = useStreamService()

  const [websocketStats, setWebsocketStats] = createSignal<WebSocketStats | null>(null)
  const [performanceMetrics, setPerformanceMetrics] = createSignal<PerformanceMetrics | null>(null)
  const [systemInfo, setSystemInfo] = createSignal<SystemInfo | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)

  let telemetryChannel: Channel | null = null
  let reconnectTimeout: number | null = null

  const connectToTelemetry = () => {
    const socketWrapper = getSocket()
    if (!socketWrapper) {
      console.error('[TelemetryService] No socket wrapper available')
      scheduleReconnect()
      return
    }

    // Check socket state
    if (socketWrapper.connectionState !== 'connected') {
      console.log('[TelemetryService] Socket not connected, waiting...')
      scheduleReconnect()
      return
    }

    const phoenixSocket = socketWrapper.getSocket()
    if (!phoenixSocket) {
      console.error('[TelemetryService] No Phoenix socket available')
      scheduleReconnect()
      return
    }

    // Clean up existing channel if any
    if (telemetryChannel) {
      telemetryChannel.leave()
      telemetryChannel = null
    }

    console.log('[TelemetryService] Creating telemetry channel...')
    telemetryChannel = phoenixSocket.channel('dashboard:telemetry', {})

    if (!telemetryChannel) {
      console.error('[TelemetryService] Failed to create channel')
      scheduleReconnect()
      return
    }

    // Set up event listeners
    telemetryChannel.on('telemetry_update', (response: TelemetryResponse | TelemetrySnapshot) => {
      console.log('[TelemetryService] Received telemetry update')
      handleTelemetryData(response)
    })

    // Join the channel
    console.log('[TelemetryService] Joining telemetry channel...')
    const joinPush = telemetryChannel.join()

    joinPush.receive('ok', (response: any) => {
      console.log('[TelemetryService] Successfully joined telemetry channel')
      setIsConnected(true)

      // Request initial data
      requestTelemetryData()
    })

    joinPush.receive('error', (resp: any) => {
      console.error('[TelemetryService] Failed to join channel:', resp)
      setIsConnected(false)
      scheduleReconnect()
    })

    joinPush.receive('timeout', () => {
      console.error('[TelemetryService] Channel join timeout')
      setIsConnected(false)
      scheduleReconnect()
    })
  }

  const handleTelemetryData = (response: TelemetryResponse | TelemetrySnapshot) => {
    // Handle ResponseBuilder wrapper or direct data
    const data = 'data' in response && response.data ? response.data : (response as TelemetrySnapshot)

    if (data.websocket) {
      setWebsocketStats(data.websocket)
    }
    if (data.performance) {
      setPerformanceMetrics(data.performance)
    }
    if (data.system) {
      setSystemInfo(data.system)
    }
  }

  const requestTelemetryData = () => {
    if (!telemetryChannel || telemetryChannel.state !== 'joined') {
      console.warn('[TelemetryService] Cannot request data - channel not joined')
      return
    }

    telemetryChannel
      .push('get_telemetry', {})
      .receive('ok', (response: TelemetryResponse | any) => {
        console.log('[TelemetryService] Received telemetry data')
        handleTelemetryData(response)
      })
      .receive('error', (err: any) => {
        console.error('[TelemetryService] Failed to get telemetry:', err)
      })
      .receive('timeout', () => {
        console.error('[TelemetryService] get_telemetry timeout')
      })
  }

  const scheduleReconnect = () => {
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
    }

    reconnectTimeout = window.setTimeout(() => {
      console.log('[TelemetryService] Attempting reconnect...')
      connectToTelemetry()
    }, 3000)
  }

  const requestRefresh = () => {
    requestTelemetryData()
  }

  // Setup and cleanup
  onMount(() => {
    connectToTelemetry()

    // Reconnect when socket state changes
    const socketWrapper = getSocket()
    if (socketWrapper) {
      createEffect(() => {
        if (socketWrapper.connectionState === 'connected' && !isConnected()) {
          connectToTelemetry()
        }
      })
    }
  })

  onCleanup(() => {
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
    }
    if (telemetryChannel) {
      telemetryChannel.leave()
      telemetryChannel = null
    }
  })

  const contextValue: TelemetryContextValue = {
    websocketStats,
    performanceMetrics,
    systemInfo,
    isConnected,
    requestRefresh
  }

  return <TelemetryContext.Provider value={contextValue}>{props.children}</TelemetryContext.Provider>
}
