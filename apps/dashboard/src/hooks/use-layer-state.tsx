/**
 * Pure data hook for layer state consumption
 *
 * Provides access to overlay layer state from Phoenix channels.
 */

import { useOverlayChannel } from './use-phoenix-channel'

// Re-export types for backward compatibility
export type { OverlayLayerState, LayerState, StreamContent as LayerContent } from '@/types/stream'

export function useLayerState() {
  const { layerState, isConnected } = useOverlayChannel()

  return {
    layerState,
    isConnected,
    connectionState: () => ({
      connected: isConnected(),
      reconnectAttempts: 0,
      lastConnected: null,
      error: null
    }),
    requestState: () => {
      // Requesting state is handled automatically by the channel
    }
  }
}
