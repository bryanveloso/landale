/**
 * Centralized Stream Service
 *
 * Single source of truth for all Phoenix channel management.
 * Eliminates channel conflicts and provides clean command/query separation.
 */

import { createContext, useContext, createSignal, onCleanup, onMount } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { Channel } from 'phoenix'
import { createLogger } from '@landale/logger/browser'
import {
  Socket,
  ConnectionState as SocketConnectionState,
  type ConnectionEvent,
  type HealthMetrics
} from '@landale/shared/websocket'
import type {
  OverlayLayerState,
  LayerState,
  StreamQueueState,
  ConnectionState,
  ServerStreamState,
  TakeoverCommand,
  CommandResponse,
  StreamContent,
  QueueItem
} from '@/types/stream'
import type { PhoenixEvent } from '@landale/shared'
import { validateServerStreamState, validateServerQueueState, validateTakeoverCommand } from '@/types/stream'

const logger = createLogger({
  service: 'dashboard'
})

// Channel retry configuration
const CHANNEL_RETRY_CONFIG = {
  initialDelayMs: 1000, // 1 second initial delay
  maxDelayMs: 30000, // 30 seconds max delay
  maxRetries: 5, // Max 5 retry attempts
  multiplier: 2, // Double the delay each time
  jitterFactor: 0.1 // +/- 10% random jitter
}

// Connection timing constants
const CHANNEL_JOIN_DELAY_MS = 100 // Delay before starting channel joins
const CHANNEL_JOIN_SPACING_MS = 100 // Delay between channel joins
const CHANNEL_JOIN_SEQUENCE_TIMEOUT_MS = 1000 // Time to complete join sequence
const FORCE_RECONNECT_CLEANUP_DELAY_MS = 1500 // Delay before reconnecting

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

  // Channel info functions
  getChannelInfo: () => Promise<CommandResponse>
  searchCategories: (query: string) => Promise<CommandResponse>
  updateChannelInfo: (updates: ChannelInfoUpdate) => Promise<CommandResponse>

  // Utility functions
  requestState: () => void
  requestQueueState: () => void
  forceReconnect: () => void

  // Internal socket access for activity log
  getSocket: () => Socket | null

  // Health monitoring
  getHealthMetrics: () => HealthMetrics | null
}

// Channel info update type
export interface ChannelInfoUpdate {
  title?: string
  game_id?: string
  broadcaster_language?: string
}

// Phoenix error response type
interface PhoenixErrorResponse {
  error?: {
    message?: string
  }
  reason?: string
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
  let isJoiningChannels = false
  let connectionCleanupInProgress = false

  // Channel retry tracking
  let overlayChannelRetries = 0
  let overlayChannelRetryTimer: number | null = null
  let queueChannelRetries = 0
  let queueChannelRetryTimer: number | null = null

  // Other timers
  let channelJoinDelayTimer: number | null = null
  let channelJoinSpacingTimer: number | null = null
  let channelJoinSequenceTimer: number | null = null
  let forceReconnectTimer: number | null = null

  const getServerUrl = () => {
    return 'ws://saya:7175/socket'
  }

  // Calculate retry delay with exponential backoff and jitter
  const calculateRetryDelay = (attempt: number): number => {
    const { initialDelayMs, maxDelayMs, multiplier, jitterFactor } = CHANNEL_RETRY_CONFIG
    let delay = initialDelayMs * Math.pow(multiplier, attempt - 1)
    delay = Math.min(delay, maxDelayMs)
    const jitter = delay * jitterFactor * (Math.random() * 2 - 1)
    return Math.max(0, delay + jitter)
  }

  // Connection management
  const connect = () => {
    if (socket) return // Already connecting/connected

    logger.info('Connecting to server...')

    socket = new Socket({
      url: getServerUrl(),
      maxReconnectAttempts: 10,
      reconnectDelayBase: 1000,
      reconnectDelayCap: 30000,
      heartbeatInterval: 30000,
      circuitBreakerThreshold: 5,
      circuitBreakerTimeout: 300000,
      logger: (kind: string, msg: any, data?: any) => {
        // Phoenix sometimes passes objects or undefined as msg
        if (typeof msg === 'object' && msg !== null) {
          // Handle object messages (e.g., from onConnError)
          logger.debug(`Phoenix ${kind}`, { metadata: msg })
          return
        }

        const message = msg ? String(msg) : ''

        // For heartbeats, extract the reference number if present
        if (message.includes('heartbeat')) {
          const parts = message.split(' ')
          const heartbeatMsg = parts.slice(0, 2).join(' ') // "phoenix heartbeat"
          const ref = data || parts[2] // reference number
          logger.info(`${heartbeatMsg} (${ref})`)
        } else if (kind === 'transport') {
          logger.info(`Phoenix ${kind}: ${message}`)
        } else {
          logger.debug(`Phoenix ${kind}: ${message}`, data !== undefined ? { metadata: { data } } : {})
        }
      }
    })

    // Subscribe to connection state changes
    socket.onConnectionChange((event: ConnectionEvent) => {
      logger.info('Connection state changed', {
        metadata: {
          oldState: event.oldState,
          newState: event.newState,
          error: event.error?.message
        }
      })

      const isConnected = event.newState === SocketConnectionState.CONNECTED
      const metrics = socket?.getHealthMetrics()

      setConnectionState({
        connected: isConnected,
        reconnectAttempts: metrics?.reconnectAttempts ?? 0,
        lastConnected: isConnected ? new Date().toISOString() : connectionState().lastConnected,
        error: event.error?.message ?? null
      })

      if (isConnected) {
        // Add small delay to ensure connection is stable before joining channels
        channelJoinDelayTimer = setTimeout(() => {
          if (!connectionCleanupInProgress && !isJoiningChannels) {
            joinChannels()
          }
        }, CHANNEL_JOIN_DELAY_MS)
      } else if (
        event.newState === SocketConnectionState.DISCONNECTED ||
        event.newState === SocketConnectionState.FAILED
      ) {
        // Clean up channels on any disconnection
        cleanup()
      }
    })

    socket.connect()
  }

  const joinChannels = () => {
    if (!socket || isJoiningChannels || !socket.isConnected()) {
      logger.debug('Skipping channel join', {
        metadata: {
          hasSocket: !!socket,
          isJoiningChannels,
          socketConnected: socket?.isConnected()
        }
      })
      return
    }

    isJoiningChannels = true
    logger.info('Starting channel join sequence')

    // Join channels sequentially to avoid race conditions
    joinOverlayChannel()
    // Small delay between channel joins
    channelJoinSpacingTimer = setTimeout(() => {
      joinQueueChannel()
    }, CHANNEL_JOIN_SPACING_MS)

    // Reset flag after both channels have time to join
    channelJoinSequenceTimer = setTimeout(() => {
      isJoiningChannels = false
      logger.debug('Channel join sequence complete')
    }, CHANNEL_JOIN_SEQUENCE_TIMEOUT_MS)
  }

  const joinOverlayChannel = () => {
    if (!socket || overlayChannel) return

    logger.info('Joining overlay channel...')
    overlayChannel = socket.channel('stream:overlays', {})

    // Handle overlay events
    overlayChannel?.on('stream_state', (payload: unknown) => {
      logger.debug('Received stream state', { metadata: { payload } })

      if (validateServerStreamState(payload)) {
        const transformed = transformServerState(payload)
        setLayerState(transformed)
      } else {
        logger.warn('Invalid stream state payload, using fallback', { metadata: { payload } })
        // Use fallback state when payload is invalid
        setLayerState((prev) => ({
          ...prev,
          fallback_mode: true,
          last_updated: new Date().toISOString()
        }))
      }
    })

    overlayChannel?.on('show_changed', (payload: unknown) => {
      logger.info('Show changed', { metadata: { payload } })
      const data = payload as { show: string; changed_at: string }
      setLayerState((prev) => ({
        ...prev,
        current_show: data.show as OverlayLayerState['current_show'],
        last_updated: data.changed_at
      }))
    })

    overlayChannel?.on('interrupt', (payload: unknown) => {
      logger.debug('Priority interrupt', { metadata: { payload } })
      // Stream state update will handle the actual changes
    })

    overlayChannel?.on('content_update', (payload: unknown) => {
      logger.debug('Content update', { metadata: { payload } })
      // Handle real-time content updates
      setLayerState((prev) => updateLayerContent(prev, payload as PhoenixEvent))
    })

    overlayChannel?.on('takeover', (payload: unknown) => {
      logger.info('Takeover broadcast', { metadata: { payload } })
      // Overlay components will handle this directly
    })

    overlayChannel?.on('takeover_clear', (payload: unknown) => {
      logger.info('Takeover clear broadcast', { metadata: { payload } })
      // Overlay components will handle this directly
    })

    // Join with error handling and retry logic
    overlayChannel
      ?.join()
      .receive('ok', () => {
        logger.info('Successfully joined overlay channel')
        overlayChannelRetries = 0 // Reset retry count on success
        requestState()
      })
      .receive('error', (resp: Record<string, unknown>) => {
        logger.error('Failed to join overlay channel', { metadata: { error: resp } })
        overlayChannel = null // Clean up on failure

        // Retry logic
        overlayChannelRetries++
        if (overlayChannelRetries <= CHANNEL_RETRY_CONFIG.maxRetries) {
          const delay = calculateRetryDelay(overlayChannelRetries)
          logger.info(
            `Retrying overlay channel join in ${Math.round(delay)}ms (attempt ${overlayChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          )

          setConnectionState((prev) => ({
            ...prev,
            error: `Failed to join overlay channel, retrying... (${overlayChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          }))

          overlayChannelRetryTimer = setTimeout(() => {
            joinOverlayChannel()
          }, delay)
        } else {
          logger.error(`Failed to join overlay channel after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`)
          setConnectionState((prev) => ({
            ...prev,
            error: `Failed to join overlay channel after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`
          }))
        }
      })
      .receive('timeout', () => {
        logger.error('Overlay channel join timeout')
        overlayChannel = null // Clean up on timeout

        // Retry logic
        overlayChannelRetries++
        if (overlayChannelRetries <= CHANNEL_RETRY_CONFIG.maxRetries) {
          const delay = calculateRetryDelay(overlayChannelRetries)
          logger.info(
            `Retrying overlay channel join after timeout in ${Math.round(delay)}ms (attempt ${overlayChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          )

          setConnectionState((prev) => ({
            ...prev,
            error: `Overlay channel join timeout, retrying... (${overlayChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          }))

          overlayChannelRetryTimer = setTimeout(() => {
            joinOverlayChannel()
          }, delay)
        } else {
          logger.error(`Overlay channel join timed out after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`)
          setConnectionState((prev) => ({
            ...prev,
            error: `Overlay channel join timed out after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`
          }))
        }
      })
  }

  const joinQueueChannel = () => {
    if (!socket || queueChannel) return

    logger.info('Joining queue channel...')
    queueChannel = socket.channel('stream:queue', {})

    // Handle queue events
    queueChannel?.on('queue_state', (payload: unknown) => {
      logger.debug('Received queue state', { metadata: { payload } })

      if (validateServerQueueState(payload)) {
        setQueueState(payload)
      } else {
        logger.warn('Invalid queue state payload', { metadata: { payload } })
      }
    })

    queueChannel?.on('queue_item_added', (payload: unknown) => {
      logger.debug('Queue item added', { metadata: { payload } })
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

    queueChannel?.on('queue_item_processed', (payload: unknown) => {
      logger.debug('Queue item processed', { metadata: { payload } })
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

    queueChannel?.on('queue_item_expired', (payload: unknown) => {
      logger.debug('Queue item expired', { metadata: { payload } })
      const data = payload as { queue?: QueueItem[]; item?: QueueItem }
      if (data.queue) {
        setQueueState((prev) => ({
          ...prev,
          queue: data.queue!,
          active_content: prev.active_content?.id === data.item?.id ? null : prev.active_content
        }))
      }
    })

    // Join with error handling and retry logic
    queueChannel
      ?.join()
      .receive('ok', () => {
        logger.info('Successfully joined queue channel')
        queueChannelRetries = 0 // Reset retry count on success
        requestQueueState()
      })
      .receive('error', (resp: Record<string, unknown>) => {
        logger.error('Failed to join queue channel', { metadata: { error: resp } })
        queueChannel = null // Clean up on failure

        // Retry logic
        queueChannelRetries++
        if (queueChannelRetries <= CHANNEL_RETRY_CONFIG.maxRetries) {
          const delay = calculateRetryDelay(queueChannelRetries)
          logger.info(
            `Retrying queue channel join in ${Math.round(delay)}ms (attempt ${queueChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          )

          setConnectionState((prev) => ({
            ...prev,
            error: `Failed to join queue channel, retrying... (${queueChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          }))

          queueChannelRetryTimer = setTimeout(() => {
            joinQueueChannel()
          }, delay)
        } else {
          logger.error(`Failed to join queue channel after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`)
          setConnectionState((prev) => ({
            ...prev,
            error: `Failed to join queue channel after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`
          }))
        }
      })
      .receive('timeout', () => {
        logger.error('Queue channel join timeout')
        queueChannel = null // Clean up on timeout

        // Retry logic
        queueChannelRetries++
        if (queueChannelRetries <= CHANNEL_RETRY_CONFIG.maxRetries) {
          const delay = calculateRetryDelay(queueChannelRetries)
          logger.info(
            `Retrying queue channel join after timeout in ${Math.round(delay)}ms (attempt ${queueChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          )

          setConnectionState((prev) => ({
            ...prev,
            error: `Queue channel join timeout, retrying... (${queueChannelRetries}/${CHANNEL_RETRY_CONFIG.maxRetries})`
          }))

          queueChannelRetryTimer = setTimeout(() => {
            joinQueueChannel()
          }, delay)
        } else {
          logger.error(`Queue channel join timed out after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`)
          setConnectionState((prev) => ({
            ...prev,
            error: `Queue channel join timed out after ${CHANNEL_RETRY_CONFIG.maxRetries} attempts`
          }))
        }
      })
  }

  const cleanup = () => {
    if (connectionCleanupInProgress) return

    connectionCleanupInProgress = true

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
    if (overlayChannelRetryTimer) {
      clearTimeout(overlayChannelRetryTimer)
      overlayChannelRetryTimer = null
    }
    if (queueChannelRetryTimer) {
      clearTimeout(queueChannelRetryTimer)
      queueChannelRetryTimer = null
    }
    if (channelJoinDelayTimer) {
      clearTimeout(channelJoinDelayTimer)
      channelJoinDelayTimer = null
    }
    if (channelJoinSpacingTimer) {
      clearTimeout(channelJoinSpacingTimer)
      channelJoinSpacingTimer = null
    }
    if (channelJoinSequenceTimer) {
      clearTimeout(channelJoinSequenceTimer)
      channelJoinSequenceTimer = null
    }
    if (forceReconnectTimer) {
      clearTimeout(forceReconnectTimer)
      forceReconnectTimer = null
    }

    // Reset flags and retry counts
    isJoiningChannels = false
    connectionCleanupInProgress = false
    overlayChannelRetries = 0
    queueChannelRetries = 0
  }

  const disconnect = () => {
    cleanup()
    if (socket) {
      socket.shutdown()
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

    logger.info('Sending takeover', { metadata: { command } })

    return new Promise((resolve, reject) => {
      overlayChannel!
        .push('takeover', command)
        .receive('ok', (resp: Record<string, unknown>) => {
          logger.info('Takeover sent successfully', { metadata: { response: resp } })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          logger.error('Takeover send error', { metadata: { error: resp } })
          const error = resp as Record<string, unknown>
          reject(
            new Error(
              `Takeover failed: ${(error as PhoenixErrorResponse)?.error?.message || (error as PhoenixErrorResponse)?.reason || 'unknown'}`
            )
          )
        })
        .receive('timeout', () => {
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
      overlayChannel!
        .push('takeover_clear', {})
        .receive('ok', (resp: Record<string, unknown>) => {
          logger.info('Takeover cleared successfully', { metadata: { response: resp } })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          logger.error('Clear takeover error', { metadata: { error: resp } })
          const error = resp as Record<string, unknown>
          reject(
            new Error(
              `Clear failed: ${(error as PhoenixErrorResponse)?.error?.message || (error as PhoenixErrorResponse)?.reason || 'unknown'}`
            )
          )
        })
        .receive('timeout', () => {
          reject(new Error('Clear takeover timeout'))
        })
    })
  }

  const removeQueueItem = async (id: string): Promise<CommandResponse> => {
    if (!queueChannel || !connectionState().connected) {
      throw new Error('Not connected to queue channel')
    }

    logger.info('Removing queue item', { metadata: { id } })

    return new Promise((resolve, reject) => {
      queueChannel!
        .push('remove_queue_item', { id })
        .receive('ok', (resp: Record<string, unknown>) => {
          logger.info('Item removed successfully', { metadata: { response: resp } })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          logger.error('Remove item error', { metadata: { error: resp } })
          reject(new Error(`Remove failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          reject(new Error('Remove item timeout'))
        })
    })
  }

  // Utility functions
  const requestState = () => {
    if (overlayChannel) {
      overlayChannel.push('request_state', {})
    } else if (socket && socket.connectionState === SocketConnectionState.CONNECTED) {
      // Try to rejoin channels if socket is open but channel is missing
      joinOverlayChannel()
    }
  }

  const forceReconnect = () => {
    logger.info('Force reconnecting...')

    disconnect()

    // Give cleanup time to complete
    forceReconnectTimer = setTimeout(() => {
      // Reset flags before reconnecting
      isJoiningChannels = false
      connectionCleanupInProgress = false
      connect()
    }, FORCE_RECONNECT_CLEANUP_DELAY_MS)
  }

  const requestQueueState = () => {
    if (queueChannel) {
      queueChannel.push('request_queue_state', {})
    } else if (socket && socket.connectionState === SocketConnectionState.CONNECTED) {
      // Try to rejoin channels if socket is open but channel is missing
      joinQueueChannel()
    }
  }

  // Channel info command implementations
  const getChannelInfo = async (): Promise<CommandResponse> => {
    if (!overlayChannel || !connectionState().connected) {
      throw new Error('Not connected to overlay channel')
    }

    logger.info('Getting channel info')

    return new Promise((resolve, reject) => {
      overlayChannel!
        .push('get_channel_info', {})
        .receive('ok', (resp: Record<string, unknown>) => {
          logger.info('Channel info retrieved successfully', { metadata: { response: resp } })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          logger.error('Get channel info error', { metadata: { error: resp } })
          const error = resp as Record<string, unknown>
          reject(
            new Error(
              `Get channel info failed: ${(error as PhoenixErrorResponse)?.error?.message || (error as PhoenixErrorResponse)?.reason || 'unknown'}`
            )
          )
        })
        .receive('timeout', () => {
          reject(new Error('Get channel info timeout'))
        })
    })
  }

  const searchCategories = async (query: string): Promise<CommandResponse> => {
    if (!overlayChannel || !connectionState().connected) {
      throw new Error('Not connected to overlay channel')
    }

    logger.info('Searching categories', { metadata: { query } })

    return new Promise((resolve, reject) => {
      overlayChannel!
        .push('search_categories', { query })
        .receive('ok', (resp: Record<string, unknown>) => {
          logger.info('Categories search successful', { metadata: { response: resp } })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          logger.error('Search categories error', { metadata: { error: resp } })
          const error = resp as Record<string, unknown>
          reject(
            new Error(
              `Search failed: ${(error as PhoenixErrorResponse)?.error?.message || (error as PhoenixErrorResponse)?.reason || 'unknown'}`
            )
          )
        })
        .receive('timeout', () => {
          reject(new Error('Search categories timeout'))
        })
    })
  }

  const updateChannelInfo = async (updates: ChannelInfoUpdate): Promise<CommandResponse> => {
    if (!overlayChannel || !connectionState().connected) {
      throw new Error('Not connected to overlay channel')
    }

    logger.info('Updating channel info', { metadata: { updates } })

    return new Promise((resolve, reject) => {
      overlayChannel!
        .push('update_channel_info', updates)
        .receive('ok', (resp: Record<string, unknown>) => {
          logger.info('Channel info updated successfully', { metadata: { response: resp } })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp: Record<string, unknown>) => {
          logger.error('Update channel info error', { metadata: { error: resp } })
          const error = resp as Record<string, unknown>
          reject(
            new Error(
              `Update failed: ${(error as PhoenixErrorResponse)?.error?.message || (error as PhoenixErrorResponse)?.reason || 'unknown'}`
            )
          )
        })
        .receive('timeout', () => {
          reject(new Error('Update channel info timeout'))
        })
    })
  }

  // Data transformation functions
  const transformServerState = (serverState: ServerStreamState): OverlayLayerState => {
    const allContent = [
      ...(serverState.interrupt_stack || []),
      ...(serverState.active_content ? [serverState.active_content] : [])
    ]

    // Distribute content across layers based on type and show
    const layers = {
      foreground: extractLayerContent(allContent as StreamContent[], 'foreground'),
      midground: extractLayerContent(allContent as StreamContent[], 'midground'),
      background: extractLayerContent(allContent as StreamContent[], 'background')
    }

    return {
      current_show: (typeof serverState.current_show === 'string'
        ? serverState.current_show
        : 'variety') as OverlayLayerState['current_show'],
      layers,
      active_content: serverState.active_content,
      interrupt_stack: serverState.interrupt_stack || [],
      priority_level: (typeof serverState.priority_level === 'string'
        ? serverState.priority_level
        : 'ticker') as OverlayLayerState['priority_level'],
      version: serverState.metadata?.state_version || 0,
      last_updated: serverState.metadata?.last_updated || new Date().toISOString()
    }
  }

  const extractLayerContent = (allContent: StreamContent[], targetLayer: 'foreground' | 'midground' | 'background') => {
    // Find highest priority content for this layer using server-provided layer information
    const layerContent = allContent
      .filter((content) => {
        // Use the layer field if available (server provides it), otherwise default to background
        return (content.layer || 'background') === targetLayer
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
        logger.warn('Invalid content update', { metadata: { data: update.data } })
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

        logger.debug('Content updated in layer', { metadata: { layer_id, updates } })
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
    getChannelInfo,
    searchCategories,
    updateChannelInfo,
    requestState,
    requestQueueState,
    forceReconnect,
    getSocket: () => socket,
    getHealthMetrics: () => socket?.getHealthMetrics() ?? null
  }

  return <StreamServiceContext.Provider value={contextValue}>{props.children}</StreamServiceContext.Provider>
}
