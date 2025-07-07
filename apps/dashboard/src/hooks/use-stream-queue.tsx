import { createSignal, createEffect, onCleanup } from 'solid-js'
import { Channel } from 'phoenix'
import { useSocket } from '../providers/socket-provider'

export interface QueueItem {
  id: string
  type: 'ticker' | 'alert' | 'sub_train' | 'manual_override'
  priority: number
  content_type: string
  data: any
  duration?: number
  started_at?: string
  status: 'pending' | 'active' | 'expired'
  position?: number
}

export interface QueueMetrics {
  total_items: number
  active_items: number
  pending_items: number
  average_wait_time: number
  last_processed: string | null
}

export interface StreamQueueState {
  queue: QueueItem[]
  active_content: QueueItem | null
  metrics: QueueMetrics
  is_processing: boolean
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

export function useStreamQueue() {
  const { socket, isConnected } = useSocket()
  const [queueState, setQueueState] = createSignal<StreamQueueState>(DEFAULT_QUEUE_STATE)
  
  let channel: Channel | null = null
  
  const joinChannel = () => {
    const currentSocket = socket()
    if (!currentSocket) return
    
    // Join the stream queue monitoring channel
    channel = currentSocket.channel('stream:queue', {})
    
    // Handle queue state updates
    channel.on('queue_state', (payload: StreamQueueState) => {
      console.log('[StreamQueue] Received queue state:', payload)
      setQueueState(payload)
    })
    
    channel.on('queue_item_added', (payload: { item: QueueItem; queue: QueueItem[] }) => {
      console.log('[StreamQueue] Item added:', payload)
      setQueueState(prev => ({
        ...prev,
        queue: payload.queue,
        metrics: {
          ...prev.metrics,
          total_items: prev.metrics.total_items + 1,
          pending_items: payload.queue.filter(item => item.status === 'pending').length
        }
      }))
    })
    
    channel.on('queue_item_processed', (payload: { item: QueueItem; queue: QueueItem[] }) => {
      console.log('[StreamQueue] Item processed:', payload)
      setQueueState(prev => ({
        ...prev,
        queue: payload.queue,
        active_content: payload.item.status === 'active' ? payload.item : null,
        metrics: {
          ...prev.metrics,
          active_items: payload.queue.filter(item => item.status === 'active').length,
          pending_items: payload.queue.filter(item => item.status === 'pending').length,
          last_processed: new Date().toISOString()
        }
      }))
    })
    
    channel.on('queue_item_expired', (payload: { item: QueueItem; queue: QueueItem[] }) => {
      console.log('[StreamQueue] Item expired:', payload)
      setQueueState(prev => ({
        ...prev,
        queue: payload.queue,
        active_content: prev.active_content?.id === payload.item.id ? null : prev.active_content
      }))
    })
    
    channel.on('queue_metrics_updated', (payload: QueueMetrics) => {
      console.log('[StreamQueue] Metrics updated:', payload)
      setQueueState(prev => ({
        ...prev,
        metrics: payload
      }))
    })
    
    // Join channel with error handling
    channel.join()
      .receive('ok', (resp) => {
        console.log('[StreamQueue] Successfully joined queue channel', resp)
        // Request initial queue state
        channel?.push('request_queue_state', {})
      })
      .receive('error', (resp) => {
        console.error('[StreamQueue] Unable to join queue channel', resp)
      })
      .receive('timeout', () => {
        console.error('[StreamQueue] Queue channel join timeout')
      })
  }
  
  const leaveChannel = () => {
    if (channel) {
      channel.leave()
      channel = null
    }
  }
  
  const clearQueue = () => {
    if (channel && isConnected()) {
      channel.push('clear_queue', {})
        .receive('ok', (resp) => {
          console.log('[StreamQueue] Queue cleared successfully', resp)
        })
        .receive('error', (resp) => {
          console.error('[StreamQueue] Failed to clear queue', resp)
        })
    }
  }
  
  const removeQueueItem = (itemId: string) => {
    if (channel && isConnected()) {
      channel.push('remove_queue_item', { id: itemId })
        .receive('ok', (resp) => {
          console.log('[StreamQueue] Item removed successfully', resp)
        })
        .receive('error', (resp) => {
          console.error('[StreamQueue] Failed to remove item', resp)
        })
    }
  }
  
  const reorderQueue = (itemId: string, newPosition: number) => {
    if (channel && isConnected()) {
      channel.push('reorder_queue', { id: itemId, position: newPosition })
        .receive('ok', (resp) => {
          console.log('[StreamQueue] Queue reordered successfully', resp)
        })
        .receive('error', (resp) => {
          console.error('[StreamQueue] Failed to reorder queue', resp)
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
    queueState,
    isConnected,
    clearQueue,
    removeQueueItem,
    reorderQueue
  }
}