/**
 * Pure data hook for stream queue consumption
 *
 * Consumes queue state from StreamService and provides command functions.
 * This eliminates channel conflicts and provides clean data access.
 */

import { createSignal, createEffect } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import { useStreamCommands } from './use-stream-commands'
import type { StreamQueueState, ConnectionState } from '@/types/stream'

// Re-export types for backward compatibility
export type { QueueItem, QueueMetrics, StreamQueueState } from '@/types/stream'

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
  const streamService = useStreamService()
  const commands = useStreamCommands()
  const [queueState, setQueueState] = createSignal<StreamQueueState>(DEFAULT_QUEUE_STATE)
  const [connectionState, setConnectionState] = createSignal<ConnectionState>({
    connected: false,
    reconnectAttempts: 0,
    lastConnected: null,
    error: null
  })

  // Subscribe to queue state changes from StreamService
  createEffect(() => {
    const currentState = streamService.queueState()
    setQueueState(currentState)
  })

  // Subscribe to connection state changes from StreamService
  createEffect(() => {
    const currentConnection = streamService.connectionState()
    setConnectionState(currentConnection)
  })

  // Utility function to request fresh queue state
  const requestQueueState = () => {
    streamService.requestQueueState()
  }

  return {
    queueState,
    isConnected: () => connectionState().connected,
    connectionState,
    requestQueueState,

    // Queue commands with proper loading states
    clearQueue: commands.clearQueue,
    removeQueueItem: commands.removeQueueItem,
    reorderQueue: commands.reorderQueue,
    queueCommandState: commands.queueCommandState
  }
}
