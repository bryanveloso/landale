import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Socket } from 'phoenix'

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

  const getServerUrl = () => {
    if (props.serverUrl) return props.serverUrl
    
    // Auto-detect based on environment
    return window.location.hostname === 'localhost' 
      ? '/socket' 
      : 'ws://zelan:7175/socket'
  }

  onMount(() => {
    const phoenixSocket = new Socket(getServerUrl(), {
      reconnectAfterMs: (tries: number) => {
        setReconnectAttempts(tries)
        return Math.min(1000 * Math.pow(2, tries), 30000)
      },
      logger: (kind: string, msg: string, data: any) => {
        console.log(`[Phoenix ${kind}] ${msg}`, data)
      }
    })

    // Handle socket events
    phoenixSocket.onOpen(() => {
      console.log('[SocketProvider] Connected to server')
      setIsConnected(true)
      setReconnectAttempts(0)
    })

    phoenixSocket.onError((error: any) => {
      console.error('[SocketProvider] Socket error:', error)
      setIsConnected(false)
    })

    phoenixSocket.onClose(() => {
      console.log('[SocketProvider] Socket closed')
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
    <SocketContext.Provider value={{
      socket,
      isConnected,
      reconnectAttempts
    }}>
      {props.children}
    </SocketContext.Provider>
  )
}