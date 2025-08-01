import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Channel } from 'phoenix'
import { createLogger } from '@landale/logger/browser'
import { Socket, ConnectionState, type ConnectionEvent } from '@landale/shared/websocket'

interface SocketContextType {
  socket: () => Socket | null
  isConnected: () => boolean
  reconnectAttempts: () => number
  connectionState: () => ConnectionState
  healthMetrics: () => HealthMetrics | null
}

interface HealthMetrics {
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

const SocketContext = createContext<SocketContextType>()

export const useSocket = () => {
  const context = useContext(SocketContext)
  if (!context) {
    throw new Error('useSocket must be used within a SocketProvider')
  }
  return context
}

interface SocketProviderProps {
  children: JSX.Element
  serverUrl?: string
}

export const SocketProvider: Component<SocketProviderProps> = (props) => {
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  const [reconnectAttempts, setReconnectAttempts] = createSignal(0)
  const [connectionState, setConnectionState] = createSignal<ConnectionState>(ConnectionState.DISCONNECTED)
  const [healthMetrics, setHealthMetrics] = createSignal<HealthMetrics | null>(null)

  // Initialize logger
  const correlationId = `overlay-socket-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`
  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'socket-provider', correlationId })

  const getServerUrl = () => {
    if (props.serverUrl) return props.serverUrl

    // Auto-detect based on environment
    return window.location.hostname === 'localhost' ? 'ws://localhost:7175/socket' : 'ws://zelan:7175/socket'
  }

  // Update health metrics periodically
  let metricsInterval: NodeJS.Timeout | null = null

  onMount(() => {
    const serverUrl = getServerUrl()
    logger.info('Initializing resilient socket provider', {
      metadata: { serverUrl }
    })

    const socket = new Socket({
      url: serverUrl,
      maxReconnectAttempts: 10,
      reconnectDelayBase: 1000,
      reconnectDelayCap: 30000,
      heartbeatInterval: 30000,
      circuitBreakerThreshold: 5,
      circuitBreakerTimeout: 300000,
      logger: (kind: string, msg: string, data?: unknown) => {
        logger.debug('Phoenix WebSocket event', {
          metadata: { kind, message: msg, data }
        })
      }
    })

    // Subscribe to connection state changes
    socket.onConnectionChange((event: ConnectionEvent) => {
      logger.info('Connection state changed', {
        metadata: {
          oldState: event.oldState,
          newState: event.newState,
          error: event.error?.message
        }
      })

      setConnectionState(event.newState)
      setIsConnected(event.newState === ConnectionState.CONNECTED)

      // Update reconnect attempts when reconnecting
      if (event.newState === ConnectionState.RECONNECTING) {
        const metrics = socket.getHealthMetrics()
        setReconnectAttempts(metrics.reconnectAttempts)
      } else if (event.newState === ConnectionState.CONNECTED) {
        setReconnectAttempts(0)
      }

      // Emit browser event for debugging
      window.dispatchEvent(
        new CustomEvent('landale:socket:state', {
          detail: {
            state: event.newState,
            error: event.error?.message,
            metrics: socket.getHealthMetrics()
          }
        })
      )
    })

    // Start connection
    socket.connect()
    setSocket(socket)

    // Update health metrics every 5 seconds
    metricsInterval = setInterval(() => {
      const metrics = socket.getHealthMetrics()
      setHealthMetrics(metrics)

      // Log health status if there are issues
      if (metrics.heartbeatFailures > 0 || metrics.isCircuitOpen) {
        logger.warn('Health check warning', { metadata: metrics })
      }
    }, 5000)

    // Debug helper for browser console
    if (typeof window !== 'undefined') {
      ;(window as Window & { landale_socket?: unknown }).landale_socket = {
        getMetrics: () => socket.getHealthMetrics(),
        getState: () => connectionState(),
        reconnect: () => {
          socket.disconnect()
          setTimeout(() => socket.connect(), 100)
        },
        disconnect: () => socket.disconnect(),
        connect: () => socket.connect()
      }

      logger.info('Debug helper available at window.landale_socket')
    }
  })

  onCleanup(() => {
    const currentSocket = socket()
    if (currentSocket) {
      logger.info('Shutting down socket connection')
      currentSocket.shutdown()
    }

    if (metricsInterval) {
      clearInterval(metricsInterval)
    }
  })

  return (
    <SocketContext.Provider
      value={{
        socket,
        isConnected,
        reconnectAttempts,
        connectionState,
        healthMetrics
      }}>
      {props.children}
    </SocketContext.Provider>
  )
}

// Export channel hook for backward compatibility
export const useChannel = (topic: string, params?: Record<string, unknown>): Channel | null => {
  const { socket, isConnected } = useSocket()
  const [channel, setChannel] = createSignal<Channel | null>(null)

  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'use-channel', topic })

  onMount(() => {
    if (isConnected()) {
      const phoenixSocket = socket()
      if (phoenixSocket) {
        const ch = phoenixSocket.channel(topic, params)
        if (ch) {
          logger.debug('Creating channel', { metadata: { topic, params } })
          setChannel(ch)
        }
      }
    }
  })

  // Recreate channel when connection changes
  const unsubscribe = socket()?.onConnectionChange((event) => {
    if (event.newState === ConnectionState.CONNECTED) {
      const phoenixSocket = socket()
      if (phoenixSocket && !channel()) {
        const ch = phoenixSocket.channel(topic, params)
        if (ch) {
          logger.debug('Recreating channel after reconnect', { metadata: { topic, params } })
          setChannel(ch)
        }
      }
    } else if (event.newState === ConnectionState.DISCONNECTED) {
      setChannel(null)
    }
  })

  onCleanup(() => {
    const ch = channel()
    if (ch) {
      ch.leave()
    }
    unsubscribe?.()
  })

  return channel()
}
