/**
 * Centralized Stream Service
 * 
 * Single source of truth for all Phoenix channel management.
 * Eliminates channel conflicts and provides clean command/query separation.
 */

import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Socket, Channel } from 'phoenix'
import type {
  OverlayLayerState,
  LayerState,
  StreamQueueState,
  ConnectionState,
  ServerStreamState,
  TakeoverCommand,
  CommandResponse
} from '@/types/stream'
import {
  validateServerStreamState,
  validateServerQueueState,
  validateTakeoverCommand
} from '@/types/stream'

// Default states
const DEFAULT_LAYER_STATE: OverlayLayerState = {
  current_show: 'variety',
  layers: {
    foreground: { priority: 'foreground', state: 'hidden', content: null },
    midground: { priority: 'midground', state: 'hidden', content: null },
    background: { priority: 'background', state: 'hidden', content: null }
  },
  active_content: null,
  interrupt_stack: [],
  priority_level: 'ticker',
  version: 0,
  last_updated: new Date().toISOString()
}

const DEFAULT_QUEUE_STATE: StreamQueueState = {
  queue: [],
  active_content: null,
  metrics: {
    total_items: 0,
    active_items: 0,
    pending_items: 0,
    average_wait_time: 0,
    last_processed: null
  },
  is_processing: false
}

const DEFAULT_CONNECTION_STATE: ConnectionState = {
  connected: false,
  reconnectAttempts: 0,
  lastConnected: null,
  error: null
}

// Service interface
interface StreamServiceContext {
  // State getters
  layerState: () => OverlayLayerState
  queueState: () => StreamQueueState
  connectionState: () => ConnectionState
  
  // Command functions
  sendTakeover: (command: TakeoverCommand) => Promise<CommandResponse>
  clearTakeover: () => Promise<CommandResponse>
  removeQueueItem: (id: string) => Promise<CommandResponse>
  
  // Utility functions
  requestState: () => void
  requestQueueState: () => void
  forceReconnect: () => void
}

const StreamServiceContext = createContext<StreamServiceContext>()

export const useStreamService = () => {
  const context = useContext(StreamServiceContext)
  if (!context) {
    throw new Error('useStreamService must be used within a StreamServiceProvider')
  }
  return context
}

interface StreamServiceProviderProps {
  children: JSX.Element
  serverUrl?: string
}

export const StreamServiceProvider: Component<StreamServiceProviderProps> = (props) => {
  // State signals
  const [layerState, setLayerState] = createSignal<OverlayLayerState>(DEFAULT_LAYER_STATE)
  const [queueState, setQueueState] = createSignal<StreamQueueState>(DEFAULT_QUEUE_STATE)
  const [connectionState, setConnectionState] = createSignal<ConnectionState>(DEFAULT_CONNECTION_STATE)
  
  // Connection management
  let socket: Socket | null = null
  let overlayChannel: Channel | null = null
  let queueChannel: Channel | null = null
  let reconnectTimer: number | null = null
  
  const getServerUrl = () => {
    if (props.serverUrl) return props.serverUrl
    return window.location.hostname === 'localhost' ? 'ws://localhost:7175/socket' : 'ws://zelan:7175/socket'
  }

  // Connection management
  const connect = () => {
    if (socket) return // Already connecting/connected
    
    console.log('[StreamService] Connecting to server...')
    
    socket = new Socket(getServerUrl(), {
      reconnectAfterMs: (tries: number) => {
        setConnectionState(prev => ({ ...prev, reconnectAttempts: tries }))
        return Math.min(1000 * Math.pow(2, tries), 30000)
      },
      logger: (kind: string, msg: string, data: any) => {
        console.log(`[StreamService Phoenix ${kind}] ${msg}`, data)
      }
    })

    // Socket event handlers
    socket.onOpen(() => {
      console.log('[StreamService] Connected to server')
      setConnectionState({
        connected: true,
        reconnectAttempts: 0,
        lastConnected: new Date().toISOString(),
        error: null
      })
      joinChannels()
    })

    socket.onError((error: any) => {
      console.error('[StreamService] Socket error:', error)
      setConnectionState(prev => ({
        ...prev,
        connected: false,
        error: error?.message || error?.reason || 'Connection error'
      }))
    })

    socket.onClose(() => {
      console.log('[StreamService] Socket closed')
      setConnectionState(prev => ({
        ...prev,
        connected: false
      }))
      cleanup()
    })

    socket.connect()
  }

  const joinChannels = () => {
    if (!socket) return
    
    joinOverlayChannel()
    joinQueueChannel()
  }

  const joinOverlayChannel = () => {
    if (!socket || overlayChannel) return
    
    console.log('[StreamService] Joining overlay channel...')
    overlayChannel = socket.channel('stream:overlays', {})
    
    // Handle overlay events
    overlayChannel.on('stream_state', (payload: any) => {
      console.log('[StreamService] Received stream state:', payload)
      
      if (validateServerStreamState(payload)) {
        const transformed = transformServerState(payload)
        setLayerState(transformed)
      } else {
        console.warn('[StreamService] Invalid stream state payload, using fallback:', payload)
        // Use fallback state when payload is invalid
        setLayerState(prev => ({
          ...prev,
          fallback_mode: true,
          last_updated: new Date().toISOString()
        }))
      }
    })

    overlayChannel.on('show_changed', (payload: any) => {
      console.log('[StreamService] Show changed:', payload)
      setLayerState(prev => ({
        ...prev,
        current_show: payload.show,
        last_updated: payload.changed_at
      }))
    })

    overlayChannel.on('interrupt', (payload: any) => {
      console.log('[StreamService] Priority interrupt:', payload)
      // Stream state update will handle the actual changes
    })

    overlayChannel.on('content_update', (payload: any) => {
      console.log('[StreamService] Content update:', payload)
      // Handle real-time content updates
      setLayerState(prev => updateLayerContent(prev, payload))
    })

    overlayChannel.on('takeover', (payload: any) => {
      console.log('[StreamService] Takeover broadcast:', payload)
      // Overlay components will handle this directly
    })

    overlayChannel.on('takeover_clear', (payload: any) => {
      console.log('[StreamService] Takeover clear broadcast:', payload)
      // Overlay components will handle this directly
    })


    // Join with error handling
    overlayChannel.join()
      .receive('ok', () => {
        console.log('[StreamService] Successfully joined overlay channel')
        requestState()
      })
      .receive('error', (resp: any) => {
        console.error('[StreamService] Failed to join overlay channel:', resp)
        setConnectionState(prev => ({
          ...prev,
          error: `Failed to join overlay channel: ${resp?.error?.message || resp?.reason || 'unknown'}`
        }))
      })
      .receive('timeout', () => {
        console.error('[StreamService] Overlay channel join timeout')
        setConnectionState(prev => ({
          ...prev,
          error: 'Overlay channel join timeout'
        }))
      })
  }

  const joinQueueChannel = () => {
    if (!socket || queueChannel) return
    
    console.log('[StreamService] Joining queue channel...')
    queueChannel = socket.channel('stream:queue', {})
    
    // Handle queue events
    queueChannel.on('queue_state', (payload: any) => {
      console.log('[StreamService] Received queue state:', payload)
      
      if (validateServerQueueState(payload)) {
        setQueueState(payload)
      } else {
        console.warn('[StreamService] Invalid queue state payload:', payload)
      }
    })

    queueChannel.on('queue_item_added', (payload: any) => {
      console.log('[StreamService] Queue item added:', payload)
      if (payload.queue) {
        setQueueState(prev => ({
          ...prev,
          queue: payload.queue,
          metrics: {
            ...prev.metrics,
            total_items: prev.metrics.total_items + 1,
            pending_items: payload.queue.filter((item: any) => item.status === 'pending').length
          }
        }))
      }
    })

    queueChannel.on('queue_item_processed', (payload: any) => {
      console.log('[StreamService] Queue item processed:', payload)
      if (payload.queue) {
        setQueueState(prev => ({
          ...prev,
          queue: payload.queue,
          active_content: payload.item?.status === 'active' ? payload.item : null,
          metrics: {
            ...prev.metrics,
            active_items: payload.queue.filter((item: any) => item.status === 'active').length,
            pending_items: payload.queue.filter((item: any) => item.status === 'pending').length,
            last_processed: new Date().toISOString()
          }
        }))
      }
    })

    queueChannel.on('queue_item_expired', (payload: any) => {
      console.log('[StreamService] Queue item expired:', payload)
      if (payload.queue) {
        setQueueState(prev => ({
          ...prev,
          queue: payload.queue,
          active_content: prev.active_content?.id === payload.item?.id ? null : prev.active_content
        }))
      }
    })

    // Join with error handling
    queueChannel.join()
      .receive('ok', () => {
        console.log('[StreamService] Successfully joined queue channel')
        requestQueueState()
      })
      .receive('error', (resp: any) => {
        console.error('[StreamService] Failed to join queue channel:', resp)
        setConnectionState(prev => ({
          ...prev,
          error: `Failed to join queue channel: ${resp?.error?.message || resp?.reason || 'unknown'}`
        }))
      })
      .receive('timeout', () => {
        console.error('[StreamService] Queue channel join timeout')
        setConnectionState(prev => ({
          ...prev,
          error: 'Queue channel join timeout'
        }))
      })
  }

  const cleanup = () => {
    if (overlayChannel) {
      overlayChannel.leave()
      overlayChannel = null
    }
    if (queueChannel) {
      queueChannel.leave() 
      queueChannel = null
    }
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
  }

  const disconnect = () => {
    cleanup()
    if (socket) {
      socket.disconnect()
      socket = null
    }
  }

  // Command implementations
  const sendTakeover = async (command: TakeoverCommand): Promise<CommandResponse> => {
    if (!overlayChannel || !connectionState().connected) {
      throw new Error('Not connected to overlay channel')
    }

    if (!validateTakeoverCommand(command)) {
      throw new Error('Invalid takeover command')
    }

    console.log('[StreamService] Sending takeover:', command)

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Takeover command timeout'))
      }, 10000)

      overlayChannel!.push('takeover', command)
        .receive('ok', (resp: any) => {
          clearTimeout(timeout)
          console.log('[StreamService] Takeover sent successfully:', resp)
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: any) => {
          clearTimeout(timeout)
          console.error('[StreamService] Takeover send error:', resp)
          reject(new Error(`Takeover failed: ${resp?.error?.message || resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          clearTimeout(timeout)
          reject(new Error('Takeover command timeout'))
        })
    })
  }

  const clearTakeover = async (): Promise<CommandResponse> => {
    if (!overlayChannel || !connectionState().connected) {
      throw new Error('Not connected to overlay channel')
    }

    console.log('[StreamService] Clearing takeover')

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Clear takeover timeout'))
      }, 5000)

      overlayChannel!.push('takeover_clear', {})
        .receive('ok', (resp: any) => {
          clearTimeout(timeout)
          console.log('[StreamService] Takeover cleared successfully:', resp)
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: any) => {
          clearTimeout(timeout)
          console.error('[StreamService] Clear takeover error:', resp)
          reject(new Error(`Clear failed: ${resp?.error?.message || resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          clearTimeout(timeout)
          reject(new Error('Clear takeover timeout'))
        })
    })
  }

  const removeQueueItem = async (id: string): Promise<CommandResponse> => {
    if (!queueChannel || !connectionState().connected) {
      throw new Error('Not connected to queue channel')
    }

    console.log('[StreamService] Removing queue item:', id)

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Remove item timeout'))
      }, 5000)

      queueChannel!.push('remove_queue_item', { id })
        .receive('ok', (resp: any) => {
          clearTimeout(timeout)
          console.log('[StreamService] Item removed successfully:', resp)
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: any) => {
          clearTimeout(timeout)
          console.error('[StreamService] Remove item error:', resp)
          reject(new Error(`Remove failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          clearTimeout(timeout)
          reject(new Error('Remove item timeout'))
        })
    })
  }


  // Utility functions
  const requestState = () => {
    if (overlayChannel) {
      overlayChannel.push('request_state', {})
    } else if (socket && socket.connectionState() === 'open') {
      // Try to rejoin channels if socket is open but channel is missing
      joinOverlayChannel()
    }
  }

  const forceReconnect = () => {
    console.log('[StreamService] Force reconnecting...')
    disconnect()
    setTimeout(() => connect(), 1000)
  }

  const requestQueueState = () => {
    if (queueChannel) {
      queueChannel.push('request_queue_state', {})
    } else if (socket && socket.connectionState() === 'open') {
      // Try to rejoin channels if socket is open but channel is missing
      joinQueueChannel()
    }
  }

  // Data transformation functions
  const transformServerState = (serverState: ServerStreamState): OverlayLayerState => {
    const allContent = [
      ...(serverState.interrupt_stack || []),
      ...(serverState.active_content ? [serverState.active_content] : [])
    ]
    
    // Distribute content across layers based on type and show
    const layers = {
      foreground: extractLayerContent(allContent, 'foreground', serverState.current_show),
      midground: extractLayerContent(allContent, 'midground', serverState.current_show),
      background: extractLayerContent(allContent, 'background', serverState.current_show)
    }
    
    return {
      current_show: serverState.current_show as any || 'variety',
      layers,
      active_content: serverState.active_content,
      interrupt_stack: serverState.interrupt_stack || [],
      priority_level: serverState.priority_level as any || 'ticker',
      version: serverState.metadata?.state_version || 0,
      last_updated: serverState.metadata?.last_updated || new Date().toISOString()
    }
  }

  const extractLayerContent = (allContent: any[], targetLayer: 'foreground' | 'midground' | 'background', show: string) => {
    // Layer assignment logic (same as overlay system)
    const layerMapping: Record<string, Record<string, string>> = {
      ironmon: {
        alert: 'foreground',
        death_alert: 'foreground',
        elite_four_alert: 'foreground',
        shiny_encounter: 'foreground',
        sub_train: 'midground',
        level_up: 'midground',
        gym_badge: 'midground',
        ironmon_run_stats: 'background',
        recent_follows: 'background',
        emote_stats: 'background'
      },
      variety: {
        alert: 'foreground',
        raid_alert: 'foreground',
        host_alert: 'foreground',
        sub_train: 'midground',
        cheer_celebration: 'midground',
        emote_stats: 'background',
        recent_follows: 'background',
        stream_goals: 'background',
        daily_stats: 'background'
      },
      coding: {
        alert: 'foreground',
        build_failure: 'foreground',
        deployment_alert: 'foreground',
        sub_train: 'midground',
        commit_celebration: 'midground',
        commit_stats: 'background',
        build_status: 'background',
        recent_follows: 'background'
      }
    }
    
    // Find highest priority content for this layer
    const layerContent = allContent
      .filter(content => {
        const mapping = layerMapping[show] || layerMapping.variety
        return mapping[content.type] === targetLayer
      })
      .sort((a, b) => (b.priority || 0) - (a.priority || 0))[0]
    
    return {
      priority: targetLayer,
      state: layerContent ? 'active' : 'hidden',
      content: layerContent || null
    } as LayerState
  }

  const updateLayerContent = (currentState: OverlayLayerState, _update: any): OverlayLayerState => {
    // Handle real-time updates like emote increments
    // For now, just return current state - full implementation would
    // update specific content data without disrupting layer states
    return currentState
  }

  // Lifecycle management
  onMount(() => {
    connect()
  })

  onCleanup(() => {
    disconnect()
  })

  // Context value
  const contextValue: StreamServiceContext = {
    layerState,
    queueState,
    connectionState,
    sendTakeover,
    clearTakeover,
    removeQueueItem,
    requestState,
    requestQueueState,
    forceReconnect
  }

  return (
    <StreamServiceContext.Provider value={contextValue}>
      {props.children}
    </StreamServiceContext.Provider>
  )
}