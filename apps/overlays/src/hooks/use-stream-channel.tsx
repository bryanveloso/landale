import { createSignal, createEffect, onCleanup } from 'solid-js'
import { Channel } from 'phoenix'
import { useSocket } from '../providers/socket-provider'
import { createLogger } from '@landale/logger/browser'

// Phoenix types for better TypeScript support
type PhoenixResponse = { [key: string]: unknown }

export interface StreamState {
  current_show: 'ironmon' | 'variety' | 'coding'
  active_content: {
    type: string
    data: unknown
    priority: number
    duration?: number
    started_at: string
    layer?: 'foreground' | 'midground' | 'background'
  } | null
  priority_level: 'alert' | 'sub_train' | 'ticker'
  interrupt_stack: Array<{
    type: string
    priority: number
    id: string
    started_at: string
    duration?: number
    layer?: 'foreground' | 'midground' | 'background'
  }>
  ticker_rotation: Array<
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
  active_content: null,
  priority_level: 'ticker',
  interrupt_stack: [],
  ticker_rotation: [],
  metadata: {
    last_updated: new Date().toISOString(),
    state_version: 0
  }
}

export function useStreamChannel() {
  const { socket, isConnected } = useSocket()
  const [streamState, setStreamState] = createSignal<StreamState>(DEFAULT_STATE)

  let channel: Channel | null = null

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
    channel = currentSocket.channel('stream:overlays', {})

    // Handle channel events
    channel.on('stream_state', (payload: StreamState) => {
      logger.info('Stream state received', {
        metadata: {
          currentShow: payload.current_show,
          priorityLevel: payload.priority_level,
          hasActiveContent: !!payload.active_content,
          interruptCount: payload.interrupt_stack?.length || 0
        }
      })
      setStreamState(payload)
    })

    channel.on('show_changed', (payload: ShowChange) => {
      logger.info('Show changed', {
        metadata: {
          newShow: payload.show,
          game: payload.game?.name
        }
      })
      // Handle show changes for theme switching
    })

    channel.on('interrupt', (payload: unknown) => {
      logger.info('Priority interrupt received', {
        metadata: {
          type: payload.type,
          priority: payload.priority,
          id: payload.id
        }
      })
      // Handle priority interrupts
    })

    channel.on('content_update', (payload: ContentUpdate) => {
      logger.debug('Content update received', {
        metadata: {
          type: payload.type,
          timestamp: payload.timestamp
        }
      })
      // Handle real-time content updates
    })

    // Join channel with error handling
    channel
      .join()
      .receive('ok', (resp: PhoenixResponse) => {
        logger.info('Channel joined successfully', {
          operation: 'channel_join',
          metadata: { channel: 'stream:overlays', response: resp }
        })
        // Request initial state
        channel?.push('request_state', {})
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
    if (channel) {
      channel.leave()
      channel = null
    }
  }

  const sendMessage = (event: string, payload: unknown = {}) => {
    if (channel && isConnected()) {
      channel
        .push(event, payload)
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

  // Watch for socket connection changes and auto-join channel
  createEffect(() => {
    const connected = isConnected()
    if (connected && !channel) {
      joinChannel()
    } else if (!connected && channel) {
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
