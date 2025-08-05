/**
 * Resilient WebSocket Client for Phoenix Channels
 *
 * Implements the same resilience patterns as the Python services:
 * - Exponential backoff with jitter
 * - Circuit breaker pattern
 * - Connection state management
 * - Health monitoring
 * - Graceful degradation
 * - Message inspection for debugging
 */

import { Socket as PhoenixSocket, Channel } from 'phoenix'
import { MessageInspector } from './message-inspector'
import { WEBSOCKET_DEFAULTS } from './constants'

export const ConnectionState = {
  DISCONNECTED: 'disconnected',
  CONNECTING: 'connecting',
  CONNECTED: 'connected',
  RECONNECTING: 'reconnecting',
  FAILED: 'failed'
} as const

export type ConnectionState = (typeof ConnectionState)[keyof typeof ConnectionState]

export interface ConnectionEvent {
  oldState: ConnectionState
  newState: ConnectionState
  error?: Error | undefined
  timestamp: number
}

export interface SocketOptions {
  url: string
  maxReconnectAttempts?: number
  reconnectDelayBase?: number
  reconnectDelayCap?: number
  heartbeatInterval?: number
  circuitBreakerThreshold?: number
  circuitBreakerTimeout?: number
  logger?: (kind: string, msg: string, data?: unknown) => void
  params?: Record<string, unknown>
}

export interface HealthMetrics {
  connectionState: ConnectionState
  reconnectAttempts: number
  totalReconnects: number
  failedReconnects: number
  successfulConnects: number
  heartbeatFailures: number
  circuitBreakerTrips: number
  lastHeartbeat: number
  isCircuitOpen: boolean
}

export class Socket {
  private socket: PhoenixSocket | null = null
  private options: Required<SocketOptions>

  // State management
  private _connectionState: ConnectionState = ConnectionState.DISCONNECTED
  private reconnectAttempts = 0
  private shouldReconnect = true
  private connectionCallbacks: Array<(event: ConnectionEvent) => void> = []

  // Health monitoring
  private lastHeartbeat = 0

  // Circuit breaker
  private consecutiveFailures = 0
  private circuitOpenUntil = 0

  // Metrics
  private metrics = {
    totalReconnects: 0,
    failedReconnects: 0,
    successfulConnects: 0,
    circuitBreakerTrips: 0
  }

  // Connection lock to prevent concurrent attempts
  private isConnecting = false

  // Message inspector for debugging
  private messageInspector: MessageInspector

  constructor(options: SocketOptions) {
    this.options = {
      url: options.url,
      maxReconnectAttempts: options.maxReconnectAttempts ?? WEBSOCKET_DEFAULTS.MAX_RECONNECT_ATTEMPTS,
      reconnectDelayBase: options.reconnectDelayBase ?? WEBSOCKET_DEFAULTS.RECONNECT_DELAY_BASE,
      reconnectDelayCap: options.reconnectDelayCap ?? WEBSOCKET_DEFAULTS.RECONNECT_DELAY_CAP,
      heartbeatInterval: options.heartbeatInterval ?? WEBSOCKET_DEFAULTS.HEARTBEAT_INTERVAL,
      circuitBreakerThreshold: options.circuitBreakerThreshold ?? WEBSOCKET_DEFAULTS.CIRCUIT_BREAKER_THRESHOLD,
      circuitBreakerTimeout: options.circuitBreakerTimeout ?? WEBSOCKET_DEFAULTS.CIRCUIT_BREAKER_TIMEOUT,
      logger: options.logger ?? ((kind, msg, data) => console.log(`[Phoenix ${kind}] ${msg}`, data)),
      params: options.params ?? {}
    }

    // Initialize message inspector
    this.messageInspector = new MessageInspector(WEBSOCKET_DEFAULTS.MESSAGE_INSPECTOR_BUFFER_SIZE)
  }

  // Connection state management
  private emitConnectionEvent(newState: ConnectionState, error?: Error) {
    if (newState !== this._connectionState) {
      const event: ConnectionEvent = {
        oldState: this._connectionState,
        newState,
        error: error ?? undefined,
        timestamp: Date.now()
      }

      this._connectionState = newState

      this.connectionCallbacks.forEach((callback) => {
        try {
          callback(event)
        } catch (e) {
          console.error('Error in connection callback:', e)
        }
      })
    }
  }

  onConnectionChange(callback: (event: ConnectionEvent) => void) {
    this.connectionCallbacks.push(callback)
  }

  // Circuit breaker
  private isCircuitOpen(): boolean {
    if (this.circuitOpenUntil > Date.now()) {
      return true
    }

    // Reset if timeout passed
    if (this.circuitOpenUntil > 0) {
      this.options.logger('info', 'Circuit breaker timeout expired, attempting to close circuit')
      this.circuitOpenUntil = 0
      this.consecutiveFailures = 0
    }

    return false
  }

  private recordFailure() {
    this.consecutiveFailures++

    if (this.consecutiveFailures >= this.options.circuitBreakerThreshold) {
      this.circuitOpenUntil = Date.now() + this.options.circuitBreakerTimeout
      this.metrics.circuitBreakerTrips++
      this.options.logger(
        'warn',
        `Circuit breaker opened after ${this.consecutiveFailures} failures. Will retry after ${this.options.circuitBreakerTimeout}ms`
      )
    }
  }

  private recordSuccess() {
    this.consecutiveFailures = 0
    this.circuitOpenUntil = 0
  }

  // Exponential backoff with jitter
  private calculateReconnectDelay(): number {
    const baseDelay = Math.min(
      this.options.reconnectDelayBase * Math.pow(2, this.reconnectAttempts),
      this.options.reconnectDelayCap
    )

    // Add jitter (±25%)
    const jitter = baseDelay * 0.25 * (Math.random() * 2 - 1)
    return Math.max(0, baseDelay + jitter)
  }

  // Connection management
  async connect(): Promise<void> {
    if (this.isConnecting || this._connectionState === ConnectionState.CONNECTED) {
      return
    }

    if (this.isCircuitOpen()) {
      this.emitConnectionEvent(ConnectionState.FAILED, new Error('Circuit breaker is open'))
      return
    }

    this.isConnecting = true
    this.emitConnectionEvent(ConnectionState.CONNECTING)

    try {
      this.socket = new PhoenixSocket(this.options.url, {
        params: this.options.params,
        reconnectAfterMs: () => {
          // Disable Phoenix's built-in reconnect - we handle it ourselves
          return Number.MAX_SAFE_INTEGER
        },
        logger: this.options.logger,
        heartbeatIntervalMs: this.options.heartbeatInterval
      })

      // Hook into Phoenix socket messages for inspection
      const originalOnMessage = this.socket.onMessage.bind(this.socket)
      this.socket.onMessage = (msg: any) => {
        // Record incoming message
        this.messageInspector.recordIncoming(msg)
        return originalOnMessage(msg)
      }

      // Hook into push for outgoing messages
      const originalPush = this.socket.push.bind(this.socket)
      this.socket.push = (data: any) => {
        // Record outgoing message
        this.messageInspector.recordOutgoing(data)
        return originalPush(data)
      }

      // Set up event handlers
      this.socket.onOpen(() => {
        this.options.logger('info', 'Socket connected')
        this.emitConnectionEvent(ConnectionState.CONNECTED)
        this.recordSuccess()
        this.metrics.successfulConnects++
        this.reconnectAttempts = 0
        this.lastHeartbeat = Date.now()
      })

      this.socket.onError((error) => {
        this.options.logger('error', 'Socket error', error)
        this.recordFailure()
      })

      this.socket.onClose(() => {
        this.options.logger('info', 'Socket closed')

        if (this._connectionState !== ConnectionState.DISCONNECTED) {
          this.emitConnectionEvent(ConnectionState.DISCONNECTED)

          if (this.shouldReconnect && this.reconnectAttempts < this.options.maxReconnectAttempts) {
            this.scheduleReconnect()
          } else if (this.reconnectAttempts >= this.options.maxReconnectAttempts) {
            this.emitConnectionEvent(ConnectionState.FAILED, new Error('Max reconnect attempts exceeded'))
            this.metrics.failedReconnects++
          }
        }
      })

      this.lastHeartbeat = Date.now()

      this.socket.connect()
    } catch (error) {
      this.options.logger('error', 'Failed to create socket', error)
      this.recordFailure()
      this.emitConnectionEvent(ConnectionState.FAILED, error as Error)
      this.scheduleReconnect()
    } finally {
      this.isConnecting = false
    }
  }

  private scheduleReconnect() {
    if (!this.shouldReconnect || this.isCircuitOpen()) {
      return
    }

    this.reconnectAttempts++
    this.metrics.totalReconnects++
    const delay = this.calculateReconnectDelay()

    this.emitConnectionEvent(ConnectionState.RECONNECTING)
    this.options.logger('info', `Scheduling reconnect attempt ${this.reconnectAttempts} in ${delay}ms`)

    setTimeout(() => {
      if (this.shouldReconnect) {
        this.connect()
      }
    }, delay)
  }

  disconnect() {
    this.shouldReconnect = false

    if (this.socket) {
      this.socket.disconnect()
      this.socket = null
    }

    this.emitConnectionEvent(ConnectionState.DISCONNECTED)
  }

  // Channel management
  channel(topic: string, params?: Record<string, unknown>): Channel | null {
    if (!this.socket) {
      this.options.logger('warn', 'Cannot create channel - socket not connected')
      return null
    }

    return this.socket.channel(topic, params)
  }

  // Health metrics
  getHealthMetrics(): HealthMetrics {
    return {
      connectionState: this._connectionState,
      reconnectAttempts: this.reconnectAttempts,
      totalReconnects: this.metrics.totalReconnects,
      failedReconnects: this.metrics.failedReconnects,
      successfulConnects: this.metrics.successfulConnects,
      heartbeatFailures: 0,
      circuitBreakerTrips: this.metrics.circuitBreakerTrips,
      lastHeartbeat: this.lastHeartbeat,
      isCircuitOpen: this.isCircuitOpen()
    }
  }

  // Graceful shutdown
  async shutdown() {
    this.shouldReconnect = false
    this.disconnect()
    this.connectionCallbacks = []
  }

  // Access to underlying Phoenix socket (use with caution)
  getSocket(): PhoenixSocket | null {
    return this.socket
  }

  isConnected(): boolean {
    return this._connectionState === ConnectionState.CONNECTED && this.socket?.isConnected() === true
  }

  // Getter for connection state
  get connectionState(): ConnectionState {
    return this._connectionState
  }

  // Message Inspector API
  getMessageInspector(): MessageInspector {
    return this.messageInspector
  }

  enableMessageInspection(enabled = true) {
    this.messageInspector.setEnabled(enabled)
    this.options.logger('info', `Message inspection ${enabled ? 'enabled' : 'disabled'}`)
  }

  isMessageInspectionEnabled(): boolean {
    return this.messageInspector.isEnabled()
  }
}
