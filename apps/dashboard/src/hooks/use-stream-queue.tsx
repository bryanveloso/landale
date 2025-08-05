/**
 * Pure data hook for stream queue consumption
 *
 * Provides access to queue state from Phoenix channels.
 */

import { useQueueChannel } from './use-phoenix-channel'
import { useStreamCommands } from './use-stream-commands'

// Re-export types for backward compatibility
export type { QueueItem, QueueMetrics, StreamQueueState } from '@/types/stream'

export function useStreamQueue() {
  const { queueState, isConnected } = useQueueChannel()
  const commands = useStreamCommands()

  return {
    queueState,
    isConnected,
    connectionState: () => ({
      connected: isConnected(),
      reconnectAttempts: 0,
      lastConnected: null,
      error: null
    }),
    removeQueueItem: commands.removeQueueItem,
    requestQueueState: commands.requestQueueState
  }
}
