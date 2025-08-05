import { createSignal, createEffect } from 'solid-js'
import { usePhoenixService } from '@/services/phoenix-service'
import { createLogger } from '@landale/logger/browser'
import type {
  OverlayLayerState,
  StreamQueueState,
  ServerStreamState,
  TakeoverCommand,
  CommandResponse
} from '@/types/stream'

const logger = createLogger({
  service: 'dashboard'
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

export function useOverlayChannel() {
  const { overlayChannel, isConnected } = usePhoenixService()
  const [layerState, setLayerState] = createSignal<OverlayLayerState>(DEFAULT_LAYER_STATE)

  // Subscribe to channel events
  createEffect(() => {
    const channel = overlayChannel()
    if (!channel) return

    // Handle stream state updates
    channel.on('stream_state', (payload: ServerStreamState) => {
      logger.debug('Received stream state', { payload })
      // Transform server state to client state
      setLayerState(transformServerState(payload))
    })

    channel.on('show_changed', (payload: { show: string; changed_at: string }) => {
      logger.info('Show changed', { payload })
      setLayerState((prev) => ({
        ...prev,
        current_show: payload.show as OverlayLayerState['current_show'],
        last_updated: payload.changed_at
      }))
    })

    // Request initial state
    channel.push('request_state', {})
  })

  const sendTakeover = async (command: TakeoverCommand): Promise<CommandResponse> => {
    const channel = overlayChannel()
    if (!channel || !isConnected()) {
      throw new Error('Not connected to overlay channel')
    }

    return new Promise((resolve, reject) => {
      channel
        .push('takeover', command)
        .receive('ok', (resp) => {
          logger.info('Takeover sent successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp) => {
          logger.error('Takeover send error', { error: resp })
          reject(new Error(`Takeover failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          reject(new Error('Takeover command timeout'))
        })
    })
  }

  const clearTakeover = async (): Promise<CommandResponse> => {
    const channel = overlayChannel()
    if (!channel || !isConnected()) {
      throw new Error('Not connected to overlay channel')
    }

    return new Promise((resolve, reject) => {
      channel
        .push('takeover_clear', {})
        .receive('ok', (resp) => {
          logger.info('Takeover cleared successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp) => {
          logger.error('Clear takeover error', { error: resp })
          reject(new Error(`Clear failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          reject(new Error('Clear takeover timeout'))
        })
    })
  }

  const getChannelInfo = async (): Promise<CommandResponse> => {
    const channel = overlayChannel()
    if (!channel || !isConnected()) {
      throw new Error('Not connected to overlay channel')
    }

    return new Promise((resolve, reject) => {
      channel
        .push('get_channel_info', {})
        .receive('ok', (resp) => {
          logger.info('Channel info retrieved successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp) => {
          logger.error('Get channel info error', { error: resp })
          reject(new Error(`Get channel info failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          reject(new Error('Get channel info timeout'))
        })
    })
  }

  const searchCategories = async (query: string): Promise<CommandResponse> => {
    const channel = overlayChannel()
    if (!channel || !isConnected()) {
      throw new Error('Not connected to overlay channel')
    }

    return new Promise((resolve, reject) => {
      channel
        .push('search_categories', { query })
        .receive('ok', (resp) => {
          logger.info('Categories search successful', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp) => {
          logger.error('Search categories error', { error: resp })
          reject(new Error(`Search failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          reject(new Error('Search categories timeout'))
        })
    })
  }

  const updateChannelInfo = async (updates: Record<string, unknown>): Promise<CommandResponse> => {
    const channel = overlayChannel()
    if (!channel || !isConnected()) {
      throw new Error('Not connected to overlay channel')
    }

    return new Promise((resolve, reject) => {
      channel
        .push('update_channel_info', updates)
        .receive('ok', (resp) => {
          logger.info('Channel info updated successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp) => {
          logger.error('Update channel info error', { error: resp })
          reject(new Error(`Update failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          reject(new Error('Update channel info timeout'))
        })
    })
  }

  return {
    layerState,
    isConnected,
    sendTakeover,
    clearTakeover,
    getChannelInfo,
    searchCategories,
    updateChannelInfo
  }
}

export function useQueueChannel() {
  const { queueChannel, isConnected } = usePhoenixService()
  const [queueState, setQueueState] = createSignal<StreamQueueState>(DEFAULT_QUEUE_STATE)

  // Subscribe to channel events
  createEffect(() => {
    const channel = queueChannel()
    if (!channel) return

    channel.on('queue_state', (payload: StreamQueueState) => {
      logger.debug('Received queue state', { payload })
      setQueueState(payload)
    })

    channel.on('queue_item_added', (payload) => {
      logger.debug('Queue item added', { payload })
      if (payload.queue) {
        setQueueState((prev) => ({
          ...prev,
          queue: payload.queue,
          metrics: {
            ...prev.metrics,
            total_items: prev.metrics.total_items + 1,
            pending_items: payload.queue.filter((item: { status: string }) => item.status === 'pending').length
          }
        }))
      }
    })

    // Request initial state
    channel.push('request_queue_state', {})
  })

  const removeQueueItem = async (id: string): Promise<CommandResponse> => {
    const channel = queueChannel()
    if (!channel || !isConnected()) {
      throw new Error('Not connected to queue channel')
    }

    return new Promise((resolve, reject) => {
      channel
        .push('remove_queue_item', { id })
        .receive('ok', (resp) => {
          logger.info('Item removed successfully', { response: resp })
          resolve({
            status: 'ok',
            data: resp,
            timestamp: new Date().toISOString()
          })
        })
        .receive('error', (resp) => {
          logger.error('Remove item error', { error: resp })
          reject(new Error(`Remove failed: ${resp?.reason || 'unknown'}`))
        })
        .receive('timeout', () => {
          reject(new Error('Remove item timeout'))
        })
    })
  }

  return {
    queueState,
    isConnected,
    removeQueueItem
  }
}

// Helper function to transform server state
function transformServerState(serverState: ServerStreamState): OverlayLayerState {
  const allContent = [
    ...(serverState.interrupt_stack || []),
    ...(serverState.active_content ? [serverState.active_content] : [])
  ]

  // Distribute content across layers
  const layers = {
    foreground: extractLayerContent(allContent, 'foreground'),
    midground: extractLayerContent(allContent, 'midground'),
    background: extractLayerContent(allContent, 'background')
  }

  return {
    current_show: (serverState.current_show || 'variety') as OverlayLayerState['current_show'],
    layers,
    active_content: serverState.active_content,
    interrupt_stack: serverState.interrupt_stack || [],
    priority_level: (serverState.priority_level || 'ticker') as OverlayLayerState['priority_level'],
    version: serverState.metadata?.state_version || 0,
    last_updated: serverState.metadata?.last_updated || new Date().toISOString()
  }
}

function extractLayerContent(allContent: Array<{ layer?: string; priority?: number }>, targetLayer: string) {
  const layerContent = allContent
    .filter((content) => (content.layer || 'background') === targetLayer)
    .sort((a, b) => (b.priority || 0) - (a.priority || 0))[0]

  return {
    priority: targetLayer as 'foreground' | 'midground' | 'background',
    state: layerContent ? 'active' : 'hidden',
    content: layerContent || null
  }
}
