import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Socket, Channel } from 'phoenix'
import { createLogger } from '@landale/logger/browser'
import { createPhoenixSocket, isSocketConnected } from '@landale/shared/phoenix-connection'

const logger = createLogger({
  service: 'dashboard'
})

// Service interface
interface PhoenixServiceContext {
  socket: () => Socket | null
  isConnected: () => boolean

  // Channel getters
  overlayChannel: () => Channel | null
  queueChannel: () => Channel | null
  telemetryChannel: () => Channel | null

  // Utility functions
  reconnect: () => void
}

const PhoenixServiceContext = createContext<PhoenixServiceContext>()

export const usePhoenixService = () => {
  const context = useContext(PhoenixServiceContext)
  if (!context) {
    throw new Error('usePhoenixService must be used within a PhoenixServiceProvider')
  }
  return context
}

interface PhoenixServiceProviderProps {
  children: JSX.Element
}

export const PhoenixServiceProvider: Component<PhoenixServiceProviderProps> = (props) => {
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  const [overlayChannel, setOverlayChannel] = createSignal<Channel | null>(null)
  const [queueChannel, setQueueChannel] = createSignal<Channel | null>(null)
  const [telemetryChannel, setTelemetryChannel] = createSignal<Channel | null>(null)

  let connectionCheckInterval: ReturnType<typeof setInterval> | null = null

  const connect = () => {
    logger.info('Connecting to Phoenix server...')

    const phoenixSocket = createPhoenixSocket({
      url: 'ws://saya:7175/socket',
      heartbeatIntervalMs: 15000
    })

    setSocket(phoenixSocket)

    // Check connection status periodically
    connectionCheckInterval = setInterval(() => {
      const connected = isSocketConnected(phoenixSocket)
      setIsConnected(connected)

      // Join channels when connected
      if (connected && !overlayChannel()) {
        joinChannels(phoenixSocket)
      }
    }, 1000)
  }

  const joinChannels = (phoenixSocket: Socket) => {
    // Join overlay channel
    if (!overlayChannel()) {
      const channel = phoenixSocket.channel('stream:overlays', {})
      channel
        .join()
        .receive('ok', () => {
          logger.info('Joined overlay channel')
          setOverlayChannel(channel)
        })
        .receive('error', (resp) => {
          logger.error('Failed to join overlay channel', { error: resp })
        })
    }

    // Join queue channel
    if (!queueChannel()) {
      const channel = phoenixSocket.channel('stream:queue', {})
      channel
        .join()
        .receive('ok', () => {
          logger.info('Joined queue channel')
          setQueueChannel(channel)
        })
        .receive('error', (resp) => {
          logger.error('Failed to join queue channel', { error: resp })
        })
    }

    // Join telemetry channel
    if (!telemetryChannel()) {
      const channel = phoenixSocket.channel('dashboard:telemetry', {})
      channel
        .join()
        .receive('ok', () => {
          logger.info('Joined telemetry channel')
          setTelemetryChannel(channel)
        })
        .receive('error', (resp) => {
          logger.error('Failed to join telemetry channel', { error: resp })
        })
    }
  }

  const disconnect = () => {
    logger.info('Disconnecting from Phoenix server')

    // Leave channels
    overlayChannel()?.leave()
    setOverlayChannel(null)

    queueChannel()?.leave()
    setQueueChannel(null)

    telemetryChannel()?.leave()
    setTelemetryChannel(null)

    // Disconnect socket
    socket()?.disconnect()
    setSocket(null)

    if (connectionCheckInterval) {
      clearInterval(connectionCheckInterval)
      connectionCheckInterval = null
    }
  }

  const reconnect = () => {
    logger.info('Reconnecting...')
    disconnect()
    setTimeout(() => connect(), 1000)
  }

  onMount(() => {
    connect()
  })

  onCleanup(() => {
    disconnect()
  })

  const contextValue: PhoenixServiceContext = {
    socket,
    isConnected,
    overlayChannel,
    queueChannel,
    telemetryChannel,
    reconnect
  }

  return <PhoenixServiceContext.Provider value={contextValue}>{props.children}</PhoenixServiceContext.Provider>
}
