import { createSignal, createEffect, onCleanup, onMount } from 'solid-js'
import { Channel } from 'phoenix'
import { useSocket } from '../providers/socket-provider'

// Phoenix types for better TypeScript support
type PhoenixResponse = { [key: string]: any }

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

export function useStreamChannel() {
  const { socket, isConnected } = useSocket()
  const [streamState, setStreamState] = createSignal<StreamState>(DEFAULT_STATE)
  
  let channel: Channel | null = null
  
  const joinChannel = () => {
    const currentSocket = socket()
    if (!currentSocket) return
    
    // Join the stream channel
    channel = currentSocket.channel('stream:overlays', {})
    
    // Handle channel events
    channel.on('stream_state', (payload: StreamState) => {
      console.log('[StreamChannel] Received stream state:', payload)
      setStreamState(payload)
    })
    
    channel.on('show_changed', (payload: ShowChange) => {
      console.log('[StreamChannel] Show changed:', payload)
      // Handle show changes for theme switching
    })
    
    channel.on('interrupt', (payload: any) => {
      console.log('[StreamChannel] Priority interrupt:', payload)
      // Handle priority interrupts
    })
    
    channel.on('content_update', (payload: ContentUpdate) => {
      console.log('[StreamChannel] Content update:', payload)
      // Handle real-time content updates
    })
    
    // Join channel with error handling
    channel.join()
      .receive('ok', (resp: PhoenixResponse) => {
        console.log('[StreamChannel] Successfully joined channel', resp)
        // Request initial state
        channel?.push('request_state', {})
      })
      .receive('error', (resp: PhoenixResponse) => {
        console.error('[StreamChannel] Unable to join channel', resp)
      })
      .receive('timeout', () => {
        console.error('[StreamChannel] Channel join timeout')
      })
  }
  
  const leaveChannel = () => {
    if (channel) {
      channel.leave()
      channel = null
    }
  }
  
  const sendMessage = (event: string, payload: any = {}) => {
    if (channel && isConnected()) {
      channel.push(event, payload)
        .receive('ok', (resp: PhoenixResponse) => {
          console.log(`[StreamChannel] ${event} sent successfully`, resp)
        })
        .receive('error', (resp: PhoenixResponse) => {
          console.error(`[StreamChannel] ${event} failed`, resp)
        })
    } else {
      console.warn(`[StreamChannel] Cannot send ${event}: not connected`)
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