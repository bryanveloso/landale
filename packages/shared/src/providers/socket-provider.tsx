import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Socket } from 'phoenix'
import { createLogger } from '@landale/logger/browser'
import { DEFAULT_SERVER_URLS } from '../config'

interface SocketContextType {
  socket: () => Socket | null
  isConnected: () => boolean
  reconnectAttempts: () => number
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
  serviceName?: string
}

// Extend window type for development debugging
declare global {
  interface Window {
    phoenixSocket?: Socket
  }
}

/**
 * Shared socket provider for Phoenix WebSocket connections.
 * Handles connection management, reconnection logic, and logging.
 */
export const SocketProvider: Component<SocketProviderProps> = (props): JSX.Element => {
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  const [reconnectAttempts, setReconnectAttempts] = createSignal(0)
  
  // Initialize logger with service-specific context
  const correlationId = `${props.serviceName || 'socket'}-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`
  const logger = createLogger({
    service: props.serviceName || 'landale-socket',
    level: 'info'
  }).child({ module: 'socket-provider', correlationId })

  const getServerUrl = () => {
    if (props.serverUrl) return props.serverUrl
    
    // Auto-detect based on environment
    // Dashboard uses full WS URLs, overlays use relative paths in development
    const isLocalhost = window.location.hostname === 'localhost'
    
    if (isLocalhost) {
      // For overlays in development, use relative path for Vite proxy
      return props.serviceName === 'overlays' ? '/socket' : DEFAULT_SERVER_URLS.getWebSocketUrl()
    }
    
    return DEFAULT_SERVER_URLS.getWebSocketUrl()
  }

  onMount(() => {
    const serverUrl = getServerUrl()
    logger.info('Initializing socket provider', {
      metadata: { serverUrl, serviceName: props.serviceName }
    })
    
    const phoenixSocket = new Socket(serverUrl, {
      reconnectAfterMs: (tries: number) => {
        setReconnectAttempts(tries)
        const delay = Math.min(1000 * Math.pow(2, tries), 30000)
        logger.info('WebSocket reconnection attempt', {
          metadata: { attempt: tries, delay }
        })
        return delay
      },
      logger: (kind: string, msg: string, data: any) => {
        logger.debug('Phoenix WebSocket event', {
          metadata: { kind, message: msg, data }
        })
      }
    })

    // Handle socket events
    phoenixSocket.onOpen(() => {
      logger.info('Socket connection established')
      setIsConnected(true)
      setReconnectAttempts(0)
    })

    phoenixSocket.onError((error: any) => {
      logger.error('Socket connection error', {
        error: { 
          message: error?.message || 'Unknown socket error', 
          type: 'SocketError' 
        },
        metadata: { reconnectAttempts: reconnectAttempts() }
      })
      setIsConnected(false)
    })

    phoenixSocket.onClose(() => {
      logger.warn('Socket connection closed', {
        metadata: { reconnectAttempts: reconnectAttempts() }
      })
      setIsConnected(false)
    })

    // Expose socket for debugging in development
    if (import.meta.env.DEV) {
      window.phoenixSocket = phoenixSocket
    }

    // Connect and store
    phoenixSocket.connect()
    setSocket(phoenixSocket)
  })

  onCleanup(() => {
    const currentSocket = socket()
    if (currentSocket) {
      logger.info('Disconnecting socket on cleanup')
      currentSocket.disconnect()
    }
  })

  const contextValue = {
    socket,
    isConnected,
    reconnectAttempts
  }

  return (
    <SocketContext.Provider value={contextValue}>
      {props.children}
    </SocketContext.Provider>
  )
}