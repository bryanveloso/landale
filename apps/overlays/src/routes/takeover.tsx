import { createFileRoute } from '@tanstack/solid-router'
import { createEffect, createSignal, onCleanup, onMount, Show } from 'solid-js'
import type { Socket, Channel } from 'phoenix'
import { createPhoenixSocket, isSocketConnected } from '@landale/shared/phoenix-connection'
import { createLogger } from '@landale/logger/browser'

export const Route = createFileRoute('/takeover')({
  component: TakeoverOverlay
})

interface TakeoverState {
  active: boolean
  type: string
  message: string
  duration?: number
  activatedAt?: string
}

interface TakeoverPayload {
  type: string
  message: string
  duration?: number
  timestamp?: string
}

const DEFAULT_TAKEOVER_STATE: TakeoverState = {
  active: false,
  type: '',
  message: ''
}

function TakeoverOverlay() {
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  const [takeoverState, setTakeoverState] = createSignal<TakeoverState>(DEFAULT_TAKEOVER_STATE)
  const [channel, setChannel] = createSignal<Channel | null>(null)
  const [, setChannelState] = createSignal<string>('closed')

  let hideTimer: ReturnType<typeof setTimeout> | null = null
  let connectionCheckInterval: ReturnType<typeof setInterval> | null = null
  let channelStateInterval: ReturnType<typeof setInterval> | null = null

  // Initialize logger with correlation ID
  const correlationId = `overlay-takeover-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`
  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'takeover', correlationId })

  // Track channel state changes
  createEffect(() => {
    const ch = channel()
    if (ch) {
      // Update channel state immediately
      setChannelState(ch.state)

      // Poll for state changes
      if (channelStateInterval) clearInterval(channelStateInterval)
      channelStateInterval = setInterval(() => {
        setChannelState(ch.state)
      }, 100)
    } else {
      setChannelState('closed')
      if (channelStateInterval) {
        clearInterval(channelStateInterval)
        channelStateInterval = null
      }
    }
  })

  // Create Phoenix socket on mount
  onMount(() => {
    logger.info('Initializing Phoenix socket')
    const phoenixSocket = createPhoenixSocket()
    setSocket(phoenixSocket)

    // Check connection status periodically
    connectionCheckInterval = setInterval(() => {
      const connected = isSocketConnected(phoenixSocket)
      setIsConnected(connected)
    }, 1000)

    // Join channel after socket is ready
    setTimeout(() => {
      setupChannel(phoenixSocket)
    }, 100)
  })

  const setupChannel = (phoenixSocket: Socket) => {
    if (!phoenixSocket) {
      logger.debug('Skipping channel setup - no socket')
      return
    }

    logger.debug('Creating channel', {
      metadata: {
        socketConnected: isSocketConnected(phoenixSocket)
      }
    })

    const newChannel = phoenixSocket.channel('stream:overlays', {})
    setChannel(newChannel)

    // Handle takeover events
    newChannel.on('takeover', (payload: TakeoverPayload) => {
      logger.info('Takeover received', {
        metadata: {
          type: payload.type,
          duration: payload.duration,
          hasMessage: !!payload.message
        }
      })

      const newState: TakeoverState = {
        active: true,
        type: payload.type || 'custom',
        message: payload.message || '',
        duration: payload.duration,
        activatedAt: new Date().toISOString()
      }

      setTakeoverState(newState)

      // Auto-hide after duration if specified
      if (payload.duration) {
        if (hideTimer) clearTimeout(hideTimer)
        hideTimer = setTimeout(() => {
          hideTakeover()
        }, payload.duration)
      }
    })

    // Handle takeover clear events
    newChannel.on('takeover_clear', () => {
      logger.info('Takeover clear received')
      hideTakeover()
    })

    logger.debug('Attempting to join channel', {
      metadata: {
        channelState: newChannel.state
      }
    })

    newChannel
      .join()
      .receive('ok', (resp) => {
        logger.info('Channel joined successfully', {
          metadata: {
            channel: 'stream:overlays',
            channelState: newChannel.state,
            response: resp
          }
        })
      })
      .receive('error', (resp: { reason?: string }) => {
        logger.error('Channel join failed', {
          error: { message: resp?.reason || 'Unknown join error', type: 'ChannelJoinError' },
          metadata: {
            channel: 'stream:overlays',
            channelState: newChannel.state,
            response: resp
          }
        })
      })
      .receive('timeout', () => {
        logger.error('Channel join timeout', {
          error: { message: 'Join timeout', type: 'ChannelJoinTimeout' },
          metadata: {
            channel: 'stream:overlays',
            channelState: newChannel.state
          }
        })
      })
  }

  const hideTakeover = () => {
    setTakeoverState(DEFAULT_TAKEOVER_STATE)
    if (hideTimer) {
      clearTimeout(hideTimer)
      hideTimer = null
    }
  }

  onCleanup(() => {
    logger.info('Cleaning up takeover overlay')

    const ch = channel()
    if (ch) {
      ch.leave()
      setChannel(null)
    }

    const s = socket()
    if (s) {
      s.disconnect()
      setSocket(null)
    }

    if (hideTimer) {
      clearTimeout(hideTimer)
      hideTimer = null
    }

    if (connectionCheckInterval) {
      clearInterval(connectionCheckInterval)
      connectionCheckInterval = null
    }

    if (channelStateInterval) {
      clearInterval(channelStateInterval)
      channelStateInterval = null
    }
  })

  return (
    <div
      class="takeover-overlay"
      data-active={takeoverState().active}
      data-type={takeoverState().type}
      data-connected={isConnected()}>
      <Show when={takeoverState().active}>
        <TakeoverContent state={takeoverState()} onHide={hideTakeover} />
      </Show>
    </div>
  )
}

interface TakeoverContentProps {
  state: TakeoverState
  onHide: () => void
}

function TakeoverContent(props: TakeoverContentProps) {
  return (
    <div class={`takeover-content takeover-${props.state.type}`} data-type={props.state.type}>
      <Show when={props.state.type === 'technical-difficulties'}>
        <TechnicalDifficulties message={props.state.message} />
      </Show>

      <Show when={props.state.type === 'screen-cover'}>
        <ScreenCover message={props.state.message} />
      </Show>

      <Show when={props.state.type === 'please-stand-by'}>
        <PleaseStandBy message={props.state.message} />
      </Show>

      <Show when={props.state.type === 'custom'}>
        <CustomMessage message={props.state.message} />
      </Show>
    </div>
  )
}

// Takeover overlay components
function TechnicalDifficulties(props: { message: string }) {
  return (
    <div class="takeover technical-difficulties">
      <div class="takeover-title">Technical Difficulties</div>
      <div class="takeover-subtitle">{props.message || "We'll be right back!"}</div>
      <div class="takeover-logo">{/* Logo/branding would go here */}</div>
    </div>
  )
}

function ScreenCover(props: { message: string }) {
  return (
    <div class="takeover screen-cover">
      <div class="cover-content">{props.message && <div class="cover-message">{props.message}</div>}</div>
    </div>
  )
}

function PleaseStandBy(props: { message: string }) {
  return (
    <div class="takeover please-stand-by">
      <div class="standby-title">Please Stand By</div>
      {props.message && <div class="standby-message">{props.message}</div>}
    </div>
  )
}

function CustomMessage(props: { message: string }) {
  return (
    <div class="takeover custom">
      <div class="custom-message">{props.message || 'Takeover Active'}</div>
    </div>
  )
}
