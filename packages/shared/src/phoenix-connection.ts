import { Socket, Channel } from 'phoenix'
import { logger } from './logger'
import { currentEnvironment } from './environment'

export interface PhoenixConnectionOptions {
  url?: string
  heartbeatIntervalMs?: number
  params?: Record<string, unknown>
  enableDebugLogging?: boolean
}

/**
 * Create a Phoenix socket with sensible defaults
 * Automatically includes environment detection for telemetry filtering
 */
export function createPhoenixSocket(options: PhoenixConnectionOptions = {}) {
  const socketOptions: any = {
    heartbeatIntervalMs: options.heartbeatIntervalMs || 15000,
    reconnectAfterMs: (tries: number) => {
      // Phoenix's default exponential backoff is fine
      return [10, 50, 100, 150, 200, 250, 500, 1000, 2000, 5000][tries - 1] || 10000
    },
    params: {
      environment: currentEnvironment,
      ...options.params
    }
  }

  // Only add logger if debug logging is explicitly enabled
  if (options.enableDebugLogging) {
    socketOptions.logger = (kind: string, msg: string, data: any) => {
      logger.debug(`[Phoenix ${kind}] ${msg}`, data)
    }
  }

  const socket = new Socket(options.url || 'ws://saya:7175/socket', socketOptions)

  socket.connect()
  return socket
}

/**
 * Join a channel with basic error handling
 * Includes environment in channel params for filtering
 */
export function joinChannel(socket: Socket, topic: string, params = {}): Channel {
  const channelParams = {
    environment: currentEnvironment,
    ...params
  }

  const channel = socket.channel(topic, channelParams)

  channel
    .join()
    .receive('ok', (resp) => {
      logger.info(`[Channel] Joined ${topic} (env: ${currentEnvironment})`, resp)
    })
    .receive('error', (resp) => {
      logger.error(`[Channel] Failed to join ${topic}`, resp)
    })
    .receive('timeout', () => {
      logger.error(`[Channel] Join timeout for ${topic}`)
    })

  return channel
}

/**
 * Get socket connection state
 */
export function isSocketConnected(socket: Socket): boolean {
  return socket.isConnected()
}
