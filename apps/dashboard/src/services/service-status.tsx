/**
 * Service Status Service
 *
 * Centralized service for service status monitoring.
 * Handles Phoenix channel subscription and shares data between components.
 */

import { createContext, useContext, createSignal, createEffect } from 'solid-js'
import type { JSX } from 'solid-js'
import { logger } from '@landale/shared/logger'
import { usePhoenixService } from './phoenix-service'
import type { SystemInfo, ServiceMetrics, TelemetryResponse, TelemetrySnapshot, OverlayHealth } from '@/types/telemetry'

interface ServiceStatusContextValue {
  systemInfo: () => SystemInfo | null
  serviceMetrics: () => ServiceMetrics | null
  overlayHealth: () => OverlayHealth[] | null
  isConnected: () => boolean
  requestRefresh: () => void
  environmentFilter: () => string | null
  setEnvironmentFilter: (env: string | null) => void
}

const ServiceStatusContext = createContext<ServiceStatusContextValue>()

export function useServiceStatus() {
  const context = useContext(ServiceStatusContext)
  if (!context) {
    throw new Error('useServiceStatus must be used within ServiceStatusProvider')
  }
  return context
}

interface ServiceStatusProviderProps {
  children: JSX.Element
}

export function ServiceStatusProvider(props: ServiceStatusProviderProps) {
  const { telemetryChannel, isConnected } = usePhoenixService()

  const [systemInfo, setSystemInfo] = createSignal<SystemInfo | null>(null)
  const [serviceMetrics, setServiceMetrics] = createSignal<ServiceMetrics | null>(null)
  const [overlayHealth, setOverlayHealth] = createSignal<OverlayHealth[] | null>(null)
  const [environmentFilter, setEnvironmentFilter] = createSignal<string | null>(null)

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
      const filter = environmentFilter()
      const params = filter ? { environment: filter } : {}
      logger.debug('[ServiceStatus] Requesting status refresh', params)
      channel.push('get_telemetry', params)
    }
  }

  // Subscribe to telemetry updates
  createEffect(() => {
    const channel = telemetryChannel()
    if (!channel) return

    // Set up event listener
    channel.on('telemetry_update', (response: TelemetryResponse | TelemetrySnapshot) => {
      logger.debug('[ServiceStatus] Received status update')
      handleTelemetryData(response)
    })

    // Request initial data once channel is joined
    if (channel.state === 'joined') {
      requestRefresh()
    }
  })

  const contextValue: ServiceStatusContextValue = {
    systemInfo,
    serviceMetrics,
    overlayHealth,
    isConnected,
    requestRefresh,
    environmentFilter,
    setEnvironmentFilter
  }

  return <ServiceStatusContext.Provider value={contextValue}>{props.children}</ServiceStatusContext.Provider>
}
