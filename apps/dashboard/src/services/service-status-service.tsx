/**
 * Service Status Service
 *
 * Provides service status and system information from the backend ServicesChannel.
 * Replaces the old telemetry infrastructure with focused service monitoring.
 */

import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { usePhoenixService } from './phoenix-service'

// Type definitions for service status data
interface ServiceMetric {
  name: string
  status: 'healthy' | 'unhealthy' | 'unknown'
  last_check?: number
  response_time_ms?: number
  error?: string
  environment?: string
}

interface SystemInfo {
  uptime: number
  version: string
  environment: string
  status: 'healthy' | 'degraded' | 'unhealthy'
}

interface OverlayHealth {
  name: string
  connected: boolean
  environment?: string
  channelState?: string
  error?: string
}

interface TranscriptionAnalytics {
  timestamp: number
  total_transcriptions_24h: number
  confidence: {
    average: number
    min: number
    max: number
    distribution: {
      high: number
      medium: number
      low: number
    }
  }
  duration: {
    total_seconds: number
    average_duration: number
    total_text_length: number
  }
  trends: {
    confidence_trend: 'improving' | 'declining' | 'stable' | 'unknown'
    hourly_volume: Array<{ hour: string; count: number }>
    quality_trend: 'excellent' | 'good' | 'acceptable' | 'needs_attention' | 'unknown'
  }
  error?: string
}

interface ServiceStatusData {
  timestamp: number
  services: ServiceMetric[]
  system: SystemInfo
  overlays: OverlayHealth[]
  transcription?: TranscriptionAnalytics
}

// Service interface
interface ServiceStatusContext {
  systemInfo: () => SystemInfo | null
  serviceMetrics: () => ServiceMetric[] | null
  overlayHealth: () => OverlayHealth[] | null
  transcriptionAnalytics: () => TranscriptionAnalytics | null
  requestRefresh: () => void
  environmentFilter: () => string | null
  setEnvironmentFilter: (filter: string | null) => void
  isLoading: () => boolean
}

const ServiceStatusContext = createContext<ServiceStatusContext>()

export const useServiceStatus = () => {
  const context = useContext(ServiceStatusContext)
  if (!context) {
    throw new Error('useServiceStatus must be used within a ServiceStatusProvider')
  }
  return context
}

interface ServiceStatusProviderProps {
  children: JSX.Element
}

export const ServiceStatusProvider: Component<ServiceStatusProviderProps> = (props) => {
  const { telemetryChannel } = usePhoenixService()

  const [systemInfo, setSystemInfo] = createSignal<SystemInfo | null>(null)
  const [serviceMetrics, setServiceMetrics] = createSignal<ServiceMetric[] | null>(null)
  const [overlayHealth, setOverlayHealth] = createSignal<OverlayHealth[] | null>(null)
  const [transcriptionAnalytics, setTranscriptionAnalytics] = createSignal<TranscriptionAnalytics | null>(null)
  const [environmentFilter, setEnvironmentFilter] = createSignal<string | null>(null)
  const [isLoading, setIsLoading] = createSignal(false)

  let autoRefreshInterval: ReturnType<typeof setInterval> | null = null

  const requestRefresh = () => {
    const channel = telemetryChannel()
    if (channel && channel.state === 'joined') {
      setIsLoading(true)
      channel.push('get_telemetry', {})
    }
  }

  const setupChannelHandlers = () => {
    const channel = telemetryChannel()
    if (!channel) return

    // Listen for service status updates
    channel.on('telemetry_update', (data: ServiceStatusData) => {
      setIsLoading(false)

      // Apply environment filter if set
      const filter = environmentFilter()

      if (data.system) {
        setSystemInfo(data.system)
      }

      if (data.services) {
        const filteredServices = filter
          ? data.services.filter((service) => service.environment === filter)
          : data.services
        setServiceMetrics(filteredServices)
      }

      if (data.overlays) {
        const filteredOverlays = filter
          ? data.overlays.filter((overlay) => overlay.environment === filter)
          : data.overlays
        setOverlayHealth(filteredOverlays)
      }

      if (data.transcription) {
        setTranscriptionAnalytics(data.transcription)
      }
    })

    // Handle connection errors
    channel.onError(() => {
      setIsLoading(false)
    })
  }

  const startAutoRefresh = () => {
    // Refresh every 30 seconds
    autoRefreshInterval = setInterval(() => {
      requestRefresh()
    }, 30000)
  }

  const stopAutoRefresh = () => {
    if (autoRefreshInterval) {
      clearInterval(autoRefreshInterval)
      autoRefreshInterval = null
    }
  }

  onMount(() => {
    // Setup channel handlers when component mounts
    setupChannelHandlers()

    // Initial data request
    setTimeout(() => {
      requestRefresh()
    }, 1000) // Small delay to ensure channel is connected

    // Start auto-refresh
    startAutoRefresh()
  })

  onCleanup(() => {
    stopAutoRefresh()
  })

  const contextValue: ServiceStatusContext = {
    systemInfo,
    serviceMetrics,
    overlayHealth,
    transcriptionAnalytics,
    requestRefresh,
    environmentFilter,
    setEnvironmentFilter,
    isLoading
  }

  return <ServiceStatusContext.Provider value={contextValue}>{props.children}</ServiceStatusContext.Provider>
}
