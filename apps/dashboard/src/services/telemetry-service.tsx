/**
 * Telemetry Service
 *
 * Centralized service for telemetry data management.
 * Handles Phoenix channel subscription and shares data between components.
 */

import { createContext, useContext, createSignal, createEffect } from 'solid-js'
import type { JSX } from 'solid-js'
import { logger } from '@landale/shared/logger'
import { usePhoenixService } from './phoenix-service'
import type { SystemInfo, ServiceMetrics, TelemetryResponse, TelemetrySnapshot, OverlayHealth } from '@/types/telemetry'

interface TelemetryContextValue {
  systemInfo: () => SystemInfo | null
  serviceMetrics: () => ServiceMetrics | null
  overlayHealth: () => OverlayHealth[] | null
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
  const { telemetryChannel, isConnected } = usePhoenixService()

  const [systemInfo, setSystemInfo] = createSignal<SystemInfo | null>(null)
  const [serviceMetrics, setServiceMetrics] = createSignal<ServiceMetrics | null>(null)
  const [overlayHealth, setOverlayHealth] = createSignal<OverlayHealth[] | null>(null)

  const handleTelemetryData = (response: TelemetryResponse | TelemetrySnapshot) => {
    // Handle ResponseBuilder wrapper or direct data
    const data = 'data' in response && response.data ? response.data : (response as TelemetrySnapshot)

    if (data.system) {
      setSystemInfo(data.system)
    }
    if (data.services) {
      setServiceMetrics(data.services)
    }
    if (data.overlays) {
      setOverlayHealth(data.overlays)
    }
  }

  const requestRefresh = () => {
    const channel = telemetryChannel()
    if (channel && channel.state === 'joined') {
      logger.debug('[TelemetryService] Requesting telemetry refresh')
      channel.push('request_telemetry', {})
    }
  }

  // Subscribe to telemetry updates
  createEffect(() => {
    const channel = telemetryChannel()
    if (!channel) return

    // Set up event listener
    channel.on('telemetry_update', (response: TelemetryResponse | TelemetrySnapshot) => {
      logger.debug('[TelemetryService] Received telemetry update')
      handleTelemetryData(response)
    })

    // Request initial data once channel is joined
    if (channel.state === 'joined') {
      requestRefresh()
    }
  })

  const contextValue: TelemetryContextValue = {
    systemInfo,
    serviceMetrics,
    overlayHealth,
    isConnected,
    requestRefresh
  }

  return <TelemetryContext.Provider value={contextValue}>{props.children}</TelemetryContext.Provider>
}
