import { createFileRoute } from '@tanstack/solid-router'
import { createSignal, createEffect, onCleanup, Show } from 'solid-js'
import { Socket, Channel } from 'phoenix'
import { createLogger } from '@landale/logger/browser'

export const Route = createFileRoute('/emergency')({
  component: EmergencyOverlay
})

interface EmergencyState {
  active: boolean
  type: string
  message: string
  duration?: number
  activatedAt?: string
}

const DEFAULT_EMERGENCY_STATE: EmergencyState = {
  active: false,
  type: '',
  message: ''
}

function EmergencyOverlay() {
  const [emergencyState, setEmergencyState] = createSignal<EmergencyState>(DEFAULT_EMERGENCY_STATE)
  const [socket, setSocket] = createSignal<Socket | null>(null)
  const [isConnected, setIsConnected] = createSignal(false)
  
  let channel: Channel | null = null
  let hideTimer: ReturnType<typeof setTimeout> | null = null
  
  // Initialize logger with correlation ID
  const correlationId = `overlay-emergency-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`
  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'emergency', correlationId })

  // Connect to WebSocket
  createEffect(() => {
    // Use same server URL logic as StreamService
    const getServerUrl = () => {
      return window.location.hostname === 'localhost' ? 'ws://localhost:7175/socket' : 'ws://zelan:7175/socket'
    }
    
    const serverUrl = getServerUrl()
    logger.info('Initializing WebSocket connection', {
      metadata: { serverUrl }
    })
    
    const phoenixSocket = new Socket(serverUrl, {
      logger: (kind: string, msg: string, data: any) => {
        logger.debug('Phoenix WebSocket event', {
          metadata: { kind, message: msg, data }
        })
      }
    })

    phoenixSocket.onOpen(() => {
      logger.info('WebSocket connection established')
      setIsConnected(true)
      joinChannel()
    })

    phoenixSocket.onError((error: any) => {
      logger.error('WebSocket connection error', {
        error: { message: error?.message || 'Unknown socket error', type: 'WebSocketError' },
        metadata: { serverUrl }
      })
      setIsConnected(false)
    })

    phoenixSocket.onClose(() => {
      logger.warn('WebSocket connection closed')
      setIsConnected(false)
    })

    phoenixSocket.connect()
    setSocket(phoenixSocket)
  })

  const joinChannel = () => {
    const currentSocket = socket()
    if (!currentSocket) return

    channel = currentSocket.channel('stream:overlays', {})
    
    // Handle emergency override events
    channel.on('emergency_override', (payload: any) => {
      logger.info('Emergency override received', {
        metadata: {
          type: payload.type,
          duration: payload.duration,
          hasMessage: !!payload.message
        }
      })
      
      const newState: EmergencyState = {
        active: true,
        type: payload.type || 'custom',
        message: payload.message || '',
        duration: payload.duration,
        activatedAt: new Date().toISOString()
      }
      
      setEmergencyState(newState)
      
      // Auto-hide after duration if specified
      if (payload.duration) {
        if (hideTimer) clearTimeout(hideTimer)
        hideTimer = setTimeout(() => {
          hideEmergency()
        }, payload.duration)
      }
    })

    // Handle emergency clear events
    channel.on('emergency_clear', () => {
      logger.info('Emergency clear received')
      hideEmergency()
    })

    channel.join()
      .receive('ok', () => {
        logger.info('Channel joined successfully', {
          metadata: { channel: 'stream:overlays' }
        })
      })
      .receive('error', (resp: any) => {
        logger.error('Channel join failed', {
          error: { message: resp?.reason || 'Unknown join error', type: 'ChannelJoinError' },
          metadata: { channel: 'stream:overlays', response: resp }
        })
      })
  }

  const hideEmergency = () => {
    setEmergencyState(DEFAULT_EMERGENCY_STATE)
    if (hideTimer) {
      clearTimeout(hideTimer)
      hideTimer = null
    }
  }

  onCleanup(() => {
    if (channel) {
      channel.leave()
    }
    if (socket()) {
      socket()?.disconnect()
    }
    if (hideTimer) {
      clearTimeout(hideTimer)
    }
  })

  return (
    <div 
      data-emergency-overlay
      data-active={emergencyState().active}
      data-type={emergencyState().type}
      data-connected={isConnected()}
    >
      <Show when={emergencyState().active}>
        <EmergencyContent state={emergencyState()} onHide={hideEmergency} />
      </Show>

      {/* Debug info in development */}
      {import.meta.env.DEV && (
        <div data-debug-emergency>
          <div>Connected: {isConnected() ? '✓' : '✗'}</div>
          <div>Active: {emergencyState().active ? 'Yes' : 'No'}</div>
          <div>Type: {emergencyState().type}</div>
        </div>
      )}
    </div>
  )
}

interface EmergencyContentProps {
  state: EmergencyState
  onHide: () => void
}

function EmergencyContent(props: EmergencyContentProps) {
  return (
    <div data-emergency-content data-emergency-type={props.state.type}>
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

      {/* Emergency close button (development only) */}
      {import.meta.env.DEV && (
        <button 
          data-emergency-close 
          onClick={props.onHide}
        >
          Close Emergency
        </button>
      )}
    </div>
  )
}

// Emergency overlay components
function TechnicalDifficulties(props: { message: string }) {
  return (
    <div data-emergency="technical-difficulties">
      <div data-emergency-title>Technical Difficulties</div>
      <div data-emergency-subtitle>
        {props.message || 'We\'ll be right back!'}
      </div>
      <div data-emergency-logo>
        {/* Logo/branding would go here */}
      </div>
    </div>
  )
}

function ScreenCover(props: { message: string }) {
  return (
    <div data-emergency="screen-cover">
      <div data-cover-content>
        {props.message && (
          <div data-cover-message>{props.message}</div>
        )}
      </div>
    </div>
  )
}

function PleaseStandBy(props: { message: string }) {
  return (
    <div data-emergency="please-stand-by">
      <div data-standby-title>Please Stand By</div>
      {props.message && (
        <div data-standby-message>{props.message}</div>
      )}
    </div>
  )
}

function CustomMessage(props: { message: string }) {
  return (
    <div data-emergency="custom">
      <div data-custom-message>
        {props.message || 'Emergency Override Active'}
      </div>
    </div>
  )
}
