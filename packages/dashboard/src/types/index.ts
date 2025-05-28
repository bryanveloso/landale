export interface SystemStatus {
  status: 'online' | 'offline'
  timestamp: string
  uptime: {
    seconds: number
    formatted: string
  }
  memory: {
    rss: string
    heapTotal: string
    heapUsed: string
    external: string
  }
  version: string
}

export interface EmoteRainConfig {
  size: number
  lifetime: number
  gravity: number
  restitution: number
  friction: number
  airFriction: number
  spawnDelay: number
  maxEmotes: number
  rotationSpeed: number
}

export interface ConnectionState {
  state: 'idle' | 'connecting' | 'connected' | 'disconnected' | 'error'
  error?: string
}