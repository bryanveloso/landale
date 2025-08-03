/**
 * Telemetry Type Definitions
 *
 * Proper TypeScript interfaces for all telemetry data structures
 */

export interface WebSocketStats {
  total_connections: number
  active_channels: number
  channels_by_type: Record<string, number>
  recent_disconnects: number
  average_connection_duration: number
  status: string
  totals?: {
    connects: number
    disconnects: number
    joins: number
    leaves: number
  }
}

export interface SystemInfo {
  uptime: number
  version: string
  environment: string
  status: 'healthy' | 'degraded' | 'unhealthy'
}

export interface PerformanceMetrics {
  memory?: {
    total_mb: number
    processes_mb: number
    binary_mb: number
    ets_mb: number
  }
  cpu?: {
    schedulers: number
    run_queue: number
  }
  message_queue?: Record<string, number>
}

export interface ServiceMetrics {
  phononmaser: ServiceStatus
  seed: ServiceStatus
  obs: ServiceStatus
  twitch: ServiceStatus
}

export interface ServiceStatus {
  connected: boolean
  status?: string
  uptime?: number
  websocket_state?: string
  reconnect_attempts?: number
  circuit_breaker_trips?: number
  error?: string
}

export interface TelemetrySnapshot {
  timestamp: number
  websocket: WebSocketStats
  services: ServiceMetrics
  performance: PerformanceMetrics
  system: SystemInfo
}

export interface TelemetryResponse {
  success: boolean
  data: TelemetrySnapshot
  meta: {
    timestamp: string
    server_version: string
  }
}
