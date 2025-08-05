import { createFileRoute } from '@tanstack/solid-router'
import { createEffect, createSignal, onCleanup, Show } from 'solid-js'
import type { Channel } from 'phoenix'
import { SocketProvider, useSocket } from '@/providers/socket-provider'
import { createLogger } from '@landale/logger/browser'

export const Route = createFileRoute('/takeover')({
  component: () => (
    <SocketProvider>
      <TakeoverOverlay />
    </SocketProvider>
  )
})

interface TakeoverState {
  active: boolean
  type: string
  message: string
  duration?: number
  activatedAt?: string
}

const DEFAULT_TAKEOVER_STATE: TakeoverState = {
  active: false,
  type: '',
  message: ''
}

function TakeoverOverlay() {
  const { socket, isConnected } = useSocket()
  const [takeoverState, setTakeoverState] = createSignal<TakeoverState>(DEFAULT_TAKEOVER_STATE)

  let channel: Channel | null = null
  let hideTimer: ReturnType<typeof setTimeout> | null = null
  let channelJoinTimer: number | null = null

  // Initialize logger with correlation ID
  const correlationId = `overlay-takeover-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`
  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'takeover', correlationId })

  // Join channel when connected
  createEffect(() => {
    const phoenixSocket = socket()
    const connected = isConnected()

    if (connected && phoenixSocket && !channel) {
      logger.info('Socket connected, joining channel')
      // Add small delay before joining channel to ensure stability
      channelJoinTimer = window.setTimeout(() => {
        joinChannel()
      }, 100)
    } else if (!connected && channel) {
      // Clean up channel on disconnection
      logger.info('Socket disconnected, leaving channel')
      channel.leave()
      channel = null
    }
  })

  const joinChannel = () => {
    const phoenixSocket = socket()
    if (!phoenixSocket) {
      logger.debug('Skipping channel join - no socket')
      return
    }

    channel = phoenixSocket.channel('stream:overlays', {})
    if (!channel) {
      logger.error('Failed to create channel')
      return
    }

    // Handle takeover events
    channel.on('takeover', (payload: unknown) => {
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
    channel.on('takeover_clear', () => {
      logger.info('Takeover clear received')
      hideTakeover()
    })

    channel
      .join()
      .receive('ok', () => {
        logger.info('Channel joined successfully', {
          metadata: { channel: 'stream:overlays' }
        })
      })
      .receive('error', (resp: unknown) => {
        logger.error('Channel join failed', {
          error: { message: resp?.reason || 'Unknown join error', type: 'ChannelJoinError' },
          metadata: { channel: 'stream:overlays', response: resp }
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
    if (channel) {
      channel.leave()
      channel = null
    }
    if (hideTimer) {
      clearTimeout(hideTimer)
      hideTimer = null
    }
    if (channelJoinTimer) {
      clearTimeout(channelJoinTimer)
      channelJoinTimer = null
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

      {/* Debug info in development */}
      {import.meta.env.DEV && (
        <div class="debug-takeover">
          <div>Connected: {isConnected() ? '✓' : '✗'}</div>
          <div>Active: {takeoverState().active ? 'Yes' : 'No'}</div>
          <div>Type: {takeoverState().type}</div>
        </div>
      )}
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

      {/* Takeover close button (development only) */}
      {import.meta.env.DEV && (
        <button class="takeover-close" onClick={props.onHide}>
          Close Takeover
        </button>
      )}
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
