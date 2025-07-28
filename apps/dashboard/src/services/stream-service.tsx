/**
 * Centralized Stream Service
 *
 * Single source of truth for all Phoenix channel management.
 * Eliminates channel conflicts and provides clean command/query separation.
 */

import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Socket, Channel } from 'phoenix'
import { createLogger } from '@landale/logger'
import type {
  OverlayLayerState,
  LayerState,
  StreamQueueState,
  ConnectionState,
  ServerStreamState,
  TakeoverCommand,
  CommandResponse,
  StreamContent,
  QueueItem,
  ServerQueueState
} from '@/types/stream'
import type { PhoenixEvent } from '@landale/shared'
import { validateServerStreamState, validateServerQueueState, validateTakeoverCommand } from '@/types/stream'

const logger = createLogger({
  service: 'dashboard',
  defaultMeta: { module: 'StreamService' }
})

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

  // Internal socket access for activity log
  getSocket: () => Socket | null
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
    // Use an environment variable for the production/non-localhost URL
    if (import.meta.env.VITE_STREAM_SERVICE_URL) {
      return import.meta.env.VITE_STREAM_SERVICE_URL
    }
    // Fallback for development or if env var is not set
    return window.location.hostname === 'localhost' ? 'ws://localhost:7175/socket' : 'ws://zelan:7175/socket'
  }

  // Connection management
  const connect = () => {
    if (socket) return // Already connecting/connected

    logger.info('Connecting to server...')

    socket = new Socket(getServerUrl(), {
      reconnectAfterMs: (tries: number) => {
        setConnectionState((prev) => ({ ...prev, reconnectAttempts: tries }))
        return Math.min(1000 * Math.pow(2, tries), 30000)
      },
      logger: (kind: string, msg: string, data: Record<string, unknown>) => {
        logger.debug(`Phoenix ${kind}: ${msg}`, data)
      }
    })

    // Socket event handlers
    socket.onOpen(() => {
      logger.info('Connected to server')
      setConnectionState({
        connected: true,
        reconnectAttempts: 0,
        lastConnected: new Date().toISOString(),
        error: null
      })
      joinChannels()
    })

    socket.onError((error: unknown) => {
      logger.error('Socket error', { error: error instanceof Error ? error.message : String(error) })
      setConnectionState((prev) => ({
        ...prev,
        connected: false,
        error: error instanceof Error ? error.message : 'Connection error'
      }))
    })

    socket.onClose(() => {
      logger.info('Socket closed')
      setConnectionState((prev) => ({
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

    logger.info('Joining overlay channel...')
    overlayChannel = socket.channel('stream:overlays', {})

    // Handle overlay events
    overlayChannel.on('stream_state', (payload: unknown) => {
      logger.debug('Received stream state', { payload })

      if (validateServerStreamState(payload)) {
        const transformed = transformServerState(payload)
        setLayerState(transformed)
      } else {
        logger.warn('Invalid stream state payload, using fallback', { payload })
        // Use fallback state when payload is invalid
        setLayerState((prev) => ({
          ...prev,
          fallback_mode: true,
          last_updated: new Date().toISOString()
        }))
      }
    })

    overlayChannel.on('show_changed', (payload: unknown) => {
      logger.info('Show changed', { payload })
      const data = payload as { show: string; changed_at: string }
      setLayerState((prev) => ({
        ...prev,
        current_show: data.show as OverlayLayerState['current_show'],
        last_updated: data.changed_at
      }))
    })

    overlayChannel.on('interrupt', (payload: unknown) => {
      logger.debug('Priority interrupt', { payload })
      // Stream state update will handle the actual changes
    })

    overlayChannel.on('content_update', (payload: unknown) => {
      logger.debug('Content update', { payload })
      // Handle real-time content updates
      setLayerState((prev) => updateLayerContent(prev, payload))
    })

    overlayChannel.on('takeover', (payload: unknown) => {
      logger.info('Takeover broadcast', { payload })
      // Overlay components will handle this directly
    })

    overlayChannel.on('takeover_clear', (payload: unknown) => {
      logger.info('Takeover clear broadcast', { payload })
      // Overlay components will handle this directly
    })

    // Join with error handling
    overlayChannel
      .join()
      .receive('ok', () => {
        logger.info('Successfully joined overlay channel')
        requestState()
      })
      .receive('error', (resp: Record<string, unknown>) => {
        logger.error('Failed to join overlay channel', { error: resp })
        setConnectionState((prev) => ({
          ...prev,
          error: `Failed to join overlay channel: ${(resp as Record<string, unknown>)?.message || 'unknown'}`
        }))
      })
      .receive('timeout', () => {
        logger.error('Overlay channel join timeout')
        setConnectionState((prev) => ({
          ...prev,
          error: 'Overlay channel join timeout'
        }))
      })
  }

  const joinQueueChannel = () => {
    if (!socket || queueChannel) return

    logger.info('Joining queue channel...')
    queueChannel = socket.channel('stream:queue', {})

    // Handle queue events
    queueChannel.on('queue_state', (payload: unknown) => {
      logger.debug('Received queue state', { payload })

      if (validateServerQueueState(payload)) {
        setQueueState(payload)
      } else {
        logger.warn('Invalid queue state payload', { payload })
      }
    })

    queueChannel.on('queue_item_added', (payload: unknown) => {
      logger.debug('Queue item added', { payload })
      const data = payload as { queue?: QueueItem[] }
      if (data.queue) {
        setQueueState((prev) => ({
          ...prev,
          queue: data.queue!,
          metrics: {
            ...prev.metrics,
            total_items: prev.metrics.total_items + 1,
            pending_items: data.queue!.filter((item) => item.status === 'pending').length
          }
        }))
      }
    })

    queueChannel.on('queue_item_processed', (payload: unknown) => {
      logger.debug('Queue item processed', { payload })
      const data = payload as { queue?: QueueItem[]; item?: QueueItem }
      if (data.queue) {
        setQueueState((prev) => ({
          ...prev,
          queue: data.queue!,
          active_content: data.item?.status === 'active' ? data.item : null,
          metrics: {
            ...prev.metrics,
            active_items: data.queue!.filter((item) => item.status === 'active').length,
            pending_items: data.queue!.filter((item) => item.status === 'pending').length,
            last_processed: new Date().toISOString()
          }
        }))
      }
    })

    queueChannel.on('queue_item_expired', (payload: unknown) => {
      logger.debug('Queue item expired', { payload })
      const data = payload as { queue?: QueueItem[]; item?: QueueItem }
      if (data.queue) {
        setQueueState((prev) => ({
          ...prev,
          queue: data.queue!,
          active_content: prev.active_content?.id === data.item?.id ? null : prev.active_content
        }))
      }
    })

    // Join with error handling
    queueChannel
      .join()
      .receive('ok', () => {
        logger.info('Successfully joined queue channel')
        requestQueueState()
      })
      .receive('error', (resp: Record<string, unknown>) => {
        logger.error('Failed to join queue channel', { error: resp })
        setConnectionState((prev) => ({
          ...prev,
          error: `Failed to join queue channel: ${(resp as Record<string, unknown>)?.message || 'unknown'}`
        }))
      })
      .receive('timeout', () => {
        logger.error('Queue channel join timeout')
        setConnectionState((prev) => ({
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

    logger.info('Sending takeover', { command })

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Takeover command timeout'))
      }, 10000)

      overlayChannel!
        .push('takeover', command)
        .receive('ok', (resp: Record<string, unknown>) => {
          clearTimeout(timeout)
          logger.info('Takeover sent successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          clearTimeout(timeout)
          logger.error('Takeover send error', { error: resp })
          const error = resp as Record<string, unknown>
          reject(new Error(`Takeover failed: ${error?.error?.message || error?.reason || 'unknown'}`))
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

    logger.info('Clearing takeover')

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Clear takeover timeout'))
      }, 5000)

      overlayChannel!
        .push('takeover_clear', {})
        .receive('ok', (resp: Record<string, unknown>) => {
          clearTimeout(timeout)
          logger.info('Takeover cleared successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          clearTimeout(timeout)
          logger.error('Clear takeover error', { error: resp })
          const error = resp as Record<string, unknown>
          reject(new Error(`Clear failed: ${error?.error?.message || error?.reason || 'unknown'}`))
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

    logger.info('Removing queue item', { id })

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Remove item timeout'))
      }, 5000)

      queueChannel!
        .push('remove_queue_item', { id })
        .receive('ok', (resp: Record<string, unknown>) => {
          clearTimeout(timeout)
          logger.info('Item removed successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          clearTimeout(timeout)
          logger.error('Remove item error', { error: resp })
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
    logger.info('Force reconnecting...')
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
      foreground: extractLayerContent(allContent as StreamContent[], 'foreground', serverState.current_show),
      midground: extractLayerContent(allContent as StreamContent[], 'midground', serverState.current_show),
      background: extractLayerContent(allContent as StreamContent[], 'background', serverState.current_show)
    }

    return {
      current_show: (typeof serverState.current_show === 'string' ? serverState.current_show : 'variety') as OverlayLayerState['current_show'],
      layers,
      active_content: serverState.active_content,
      interrupt_stack: serverState.interrupt_stack || [],
      priority_level: (typeof serverState.priority_level === 'string' ? serverState.priority_level : 'ticker') as OverlayLayerState['priority_level'],
      version: serverState.metadata?.state_version || 0,
      last_updated: serverState.metadata?.last_updated || new Date().toISOString()
    }
  }

  const extractLayerContent = (
    allContent: StreamContent[],
    targetLayer: 'foreground' | 'midground' | 'background',
    show: string
  ) => {
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
      .filter((content) => {
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

  const updateLayerContent = (currentState: OverlayLayerState, update: PhoenixEvent): OverlayLayerState => {
    // Handle real-time updates like emote increments
    if (update.type === 'content_update' && update.data) {
      const { layer_id, content_id, updates } = update.data
      
      if (!layer_id || !updates) {
        logger.warn('Invalid content update', { data: update.data })
        return currentState
      }
      
      // Update content in the specified layer
      const newState = { ...currentState }
      const layer = newState.layers[layer_id as keyof typeof newState.layers]
      
      if (layer && layer.content && (!content_id || layer.content.id === content_id)) {
        // Merge updates into existing content data
        layer.content = {
          ...layer.content,
          data: {
            ...layer.content.data,
            ...updates
          }
        }
        
        newState.version = currentState.version + 1
        newState.last_updated = new Date().toISOString()
        
        logger.debug('Content updated in layer', { layer_id, updates })
        return newState
      }
    }
    
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
    forceReconnect,
    getSocket: () => socket
  }

  return <StreamServiceContext.Provider value={contextValue}>{props.children}</StreamServiceContext.Provider>
}
