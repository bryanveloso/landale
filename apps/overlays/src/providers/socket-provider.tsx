import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Socket } from 'phoenix'
import { createLogger } from '@landale/logger/browser'

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
}

export const SocketProvider: Component<SocketProviderProps> = (props) => {
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  const [reconnectAttempts, setReconnectAttempts] = createSignal(0)

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

  onMount(() => {
    const serverUrl = getServerUrl()
    logger.info('Initializing socket provider', {
      metadata: { serverUrl }
    })

    const phoenixSocket = new Socket(serverUrl, {
      reconnectAfterMs: (tries: number) => {
        setReconnectAttempts(tries)
        logger.info('WebSocket reconnection attempt', {
          metadata: { attempt: tries, delay: Math.min(1000 * Math.pow(2, tries), 30000) }
        })
        return Math.min(1000 * Math.pow(2, tries), 30000)
      },
      logger: (kind: string, msg: string, data: unknown) => {
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

    phoenixSocket.onError((error: unknown) => {
      logger.error('Socket connection error', {
        error: { message: error?.message || 'Unknown socket error', type: 'SocketError' },
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

    // Connect and store
    phoenixSocket.connect()
    setSocket(phoenixSocket)
  })

  onCleanup(() => {
    const currentSocket = socket()
    if (currentSocket) {
      currentSocket.disconnect()
    }
  })

  return (
    <SocketContext.Provider
      value={{
        socket,
        isConnected,
        reconnectAttempts
      }}>
      {props.children}
    </SocketContext.Provider>
  )
}
