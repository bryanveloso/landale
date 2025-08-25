import { createSignal, createEffect, onCleanup, onMount } from 'solid-js'
import { Channel, Socket } from 'phoenix'
import { createPhoenixSocket, isSocketConnected } from '@landale/shared/phoenix-connection'
import { createLogger } from '@landale/logger/browser'

// Phoenix types for better TypeScript support
type PhoenixResponse = { [key: string]: unknown }

export interface StreamState {
  current_show: 'ironmon' | 'variety' | 'coding'
  current: {
    type: string
    data: unknown
    priority: number
    duration?: number
    started_at: string
    layer?: 'foreground' | 'midground' | 'background'
  } | null
  base: {
    type: string
    data: unknown
    priority: number
    duration?: number
    started_at: string
    layer?: 'foreground' | 'midground' | 'background'
  } | null
  priority_level: 'alert' | 'sub_train' | 'ticker'
  alerts: Array<{
    type: string
    priority: number
    id: string
    started_at: string
    duration?: number
    layer?: 'foreground' | 'midground' | 'background'
  }>
  ticker: Array<
    | string
    | {
        type: string
        layer: 'foreground' | 'midground' | 'background'
      }
  >
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
  data: unknown
  timestamp: number
}

const DEFAULT_STATE: StreamState = {
  current_show: 'variety',
  current: null,
  base: null,
  priority_level: 'ticker',
  alerts: [],
  ticker: [],
  metadata: {
    last_updated: new Date().toISOString(),
    state_version: 0
  }
}

export function useStreamChannel() {
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  const [streamState, setStreamState] = createSignal<StreamState>(DEFAULT_STATE)
  const [channel, setChannel] = createSignal<Channel | null>(null)

  // Initialize logger
  const correlationId = `overlay-stream-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`
  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'stream-channel', correlationId })

  const joinChannel = () => {
    const currentSocket = socket()
    if (!currentSocket) return

    // Join the stream channel
    const newChannel = currentSocket.channel('stream:overlays', {})
    setChannel(newChannel)

    // Handle channel events
    newChannel.on('stream_state', (payload: StreamState) => {
      logger.info('Stream state received', {
        metadata: {
          currentShow: payload.current_show,
          priorityLevel: payload.priority_level,
          hasCurrentContent: !!payload.current,
          hasBaseContent: !!payload.base,
          alertsCount: payload.alerts?.length || 0
        }
      })
      setStreamState(payload)
    })

    newChannel.on('show_changed', (payload: ShowChange) => {
      logger.info('Show changed', {
        metadata: {
          newShow: payload.show,
          game: payload.game?.name
        }
      })
      // Handle show changes for theme switching
    })

    newChannel.on('interrupt', (payload: unknown) => {
      logger.info('Priority interrupt received', {
        metadata: {
          type: payload.type,
          priority: payload.priority,
          id: payload.id
        }
      })
      // Handle priority interrupts
    })

    newChannel.on('content_update', (payload: ContentUpdate) => {
      logger.debug('Content update received', {
        metadata: {
          type: payload.type,
          timestamp: payload.timestamp
        }
      })
      // Handle real-time content updates
      if (payload.type === 'goals_update') {
        // Update the stream state with new goals data
        setStreamState((prev) => ({
          ...prev,
          current: prev.current?.type === 'stream_goals' ? { ...prev.current, data: payload.data } : prev.current
        }))
      }
    })

    // Join channel with error handling
    newChannel
      .join()
      .receive('ok', (resp: PhoenixResponse) => {
        logger.info('Channel joined successfully', {
          operation: 'channel_join',
          metadata: { channel: 'stream:overlays', response: resp }
        })
        // Request initial state
        newChannel?.push('request_state', {})
      })
      .receive('error', (resp: PhoenixResponse) => {
        logger.error('Channel join failed', {
          operation: 'channel_join',
          error: { message: resp?.reason || 'Unknown join error', type: 'ChannelJoinError' },
          metadata: { channel: 'stream:overlays', response: resp }
        })
      })
      .receive('timeout', () => {
        logger.error('Channel join timeout', {
          operation: 'channel_join',
          error: { message: 'Join operation timed out', type: 'ChannelJoinTimeout' },
          metadata: { channel: 'stream:overlays' }
        })
      })
  }

  const leaveChannel = () => {
    const ch = channel()
    if (ch) {
      ch.leave()
      setChannel(null)
    }
  }

  const sendMessage = (event: string, payload: unknown = {}) => {
    const ch = channel()
    if (ch && isConnected()) {
      ch.push(event, payload)
        .receive('ok', (resp: PhoenixResponse) => {
          logger.debug('Message sent successfully', {
            operation: event,
            metadata: { response: resp }
          })
        })
        .receive('error', (resp: PhoenixResponse) => {
          logger.error('Message send failed', {
            operation: event,
            error: { message: resp?.reason || 'Unknown send error', type: 'MessageSendError' },
            metadata: { payload, response: resp }
          })
        })
    } else {
      logger.warn('Cannot send message: not connected', {
        operation: event,
        metadata: { payload, connected: isConnected() }
      })
    }
  }

  // Initialize Phoenix socket on mount
  onMount(() => {
    const phoenixSocket = createPhoenixSocket()
    setSocket(phoenixSocket)

    // Check connection status periodically
    const checkInterval = setInterval(() => {
      setIsConnected(isSocketConnected(phoenixSocket))
    }, 1000)

    onCleanup(() => {
      clearInterval(checkInterval)
      phoenixSocket.disconnect()
    })
  })

  // Watch for socket connection changes and auto-join channel
  createEffect(() => {
    const connected = isConnected()
    if (connected && !channel()) {
      joinChannel()
    } else if (!connected && channel()) {
      leaveChannel()
    }
  })

  // Cleanup on unmount
  onCleanup(() => {
    leaveChannel()
  })

  return {
    streamState,
    isConnected,
    sendMessage
  }
}
