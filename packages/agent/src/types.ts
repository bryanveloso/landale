export interface AgentConfig {
  id: string
  name: string
  host: string
  serverUrl: string
  reconnectInterval?: number
  heartbeatInterval?: number
}

export interface AgentCapability {
  name: string
  description: string
  actions: string[]
}

export interface AgentStatus {
  id: string
  name: string
  host: string
  status: 'online' | 'offline' | 'error'
  lastSeen: Date
  capabilities: AgentCapability[]
  metrics?: Record<string, unknown>
}

export interface AgentCommand {
  id: string
  action: string
  params?: Record<string, unknown>
  timestamp: Date
}

export interface AgentResponse {
  commandId: string
  success: boolean
  result?: unknown
  error?: string
  timestamp: Date
}

export interface ProcessInfo {
  name: string
  pid?: number
  status: 'running' | 'stopped' | 'unknown'
  cpu?: number
  memory?: number
  uptime?: number
}

export interface ServiceHealth {
  name: string
  status: 'healthy' | 'unhealthy' | 'unknown'
  message?: string
  lastCheck: Date
}