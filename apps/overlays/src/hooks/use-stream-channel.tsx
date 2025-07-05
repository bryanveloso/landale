import { createSignal, createEffect, onCleanup, onMount } from 'solid-js'

export interface StreamState {
  current_show: 'ironmon' | 'variety' | 'coding'
  active_content: {
    type: string
    data: any
    priority: number
    duration?: number
    started_at: string
  } | null
  priority_level: 'alert' | 'sub_train' | 'ticker'
  interrupt_stack: Array<{
    type: string
    priority: number
    id: string
    started_at: string
    duration?: number
  }>
  ticker_rotation: string[]
  metadata: {
    last_updated: string
    state_version: number
  }
}

export interface ShowChange {
  show: 'ironmon' | 'variety' | 'coding'
  game: {
    id: string
    name: string
  }
  changed_at: string
}

export interface ContentUpdate {
  type: string
  data: any
  timestamp: number
}

const DEFAULT_STATE: StreamState = {
  current_show: 'variety',
  active_content: null,
  priority_level: 'ticker',
  interrupt_stack: [],
  ticker_rotation: [],
  metadata: {
    last_updated: new Date().toISOString(),
    state_version: 0
  }
}

export function useStreamChannel(serverUrl: string = 'ws://zelan:7175/socket') {
  const [streamState, setStreamState] = createSignal<StreamState>(DEFAULT_STATE)
  const [isConnected, setIsConnected] = createSignal(false)
  const [reconnectAttempts, setReconnectAttempts] = createSignal(0)

  let socket: WebSocket | null = null
  let reconnectTimer: number | null = null

  const connect = () => {
    if (socket) {
      socket.close()
    }

    try {
      // Create Phoenix WebSocket connection
      socket = new WebSocket(`${serverUrl}/websocket`)

      socket.onopen = () => {
        console.log('[StreamChannel] Connected to server')
        setIsConnected(true)
        setReconnectAttempts(0)

        // Join the stream channel
        const joinMessage = {
          topic: 'stream:overlays',
          event: 'phx_join',
          payload: {},
          ref: Date.now().toString()
        }

        socket?.send(JSON.stringify(joinMessage))
      }

      socket.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data)

          console.log('[StreamChannel] Received message:', message)

          switch (message.event) {
            case 'stream_state':
              setStreamState(message.payload)
              break

            case 'show_changed':
              console.log('[StreamChannel] Show changed:', message.payload)
              // Handle show changes for theme switching
              break

            case 'interrupt':
              console.log('[StreamChannel] Priority interrupt:', message.payload)
              // Handle priority interrupts
              break

            case 'content_update':
              console.log('[StreamChannel] Content update:', message.payload)
              // Handle real-time content updates
              break

            case 'phx_reply':
              if (message.payload.status === 'ok') {
                console.log('[StreamChannel] Successfully joined channel')
                // Request initial state
                const stateRequest = {
                  topic: 'stream:overlays',
                  event: 'request_state',
                  payload: {},
                  ref: Date.now().toString()
                }
                socket?.send(JSON.stringify(stateRequest))
              }
              break

            default:
              console.log('[StreamChannel] Unhandled message:', message)
          }
        } catch (error) {
          console.error('[StreamChannel] Failed to parse message:', error)
        }
      }

      socket.onerror = (error) => {
        console.error('[StreamChannel] WebSocket error:', error)
      }

      socket.onclose = (event) => {
        console.log('[StreamChannel] Connection closed:', event.code, event.reason)
        setIsConnected(false)

        // Attempt to reconnect unless explicitly closed
        if (event.code !== 1000) {
          scheduleReconnect()
        }
      }
    } catch (error) {
      console.error('[StreamChannel] Failed to connect:', error)
      scheduleReconnect()
    }
  }

  const scheduleReconnect = () => {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
    }

    const attempts = reconnectAttempts()
    const delay = Math.min(1000 * Math.pow(2, attempts), 30000) // Max 30s delay

    console.log(`[StreamChannel] Reconnecting in ${delay}ms (attempt ${attempts + 1})`)
    setReconnectAttempts(attempts + 1)

    reconnectTimer = window.setTimeout(() => {
      connect()
    }, delay)
  }

  const disconnect = () => {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }

    if (socket) {
      socket.close(1000, 'Intentional disconnect')
      socket = null
    }
  }

  const sendPing = () => {
    if (socket && isConnected()) {
      const pingMessage = {
        topic: 'stream:overlays',
        event: 'ping',
        payload: {},
        ref: Date.now().toString()
      }

      socket.send(JSON.stringify(pingMessage))
    }
  }

  // Auto-connect on mount (only once)
  onMount(() => {
    connect()
  })

  // Cleanup on unmount
  onCleanup(() => {
    disconnect()
  })

  // Periodic ping to keep connection alive
  createEffect(() => {
    if (isConnected()) {
      const pingInterval = setInterval(sendPing, 30000) // Every 30 seconds

      onCleanup(() => {
        clearInterval(pingInterval)
      })
    }
  })

  return {
    streamState,
    isConnected,
    reconnectAttempts,
    connect,
    disconnect,
    sendPing
  }
}
