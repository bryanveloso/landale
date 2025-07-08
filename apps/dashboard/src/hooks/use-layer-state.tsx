/**
 * Pure data hook for layer state consumption
 * 
 * Consumes layer state from StreamService instead of managing Phoenix channels.
 * This eliminates channel conflicts and provides clean data access.
 */

import { createSignal, createEffect } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import type { OverlayLayerState, ConnectionState } from '@/types/stream'

// Re-export types for backward compatibility
export type { OverlayLayerState, LayerState, StreamContent as LayerContent } from '@/types/stream'

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

export function useLayerState() {
  const streamService = useStreamService()
  const [layerState, setLayerState] = createSignal<OverlayLayerState>(DEFAULT_LAYER_STATE)
  const [connectionState, setConnectionState] = createSignal<ConnectionState>({
    connected: false,
    reconnectAttempts: 0,
    lastConnected: null,
    error: null
  })
  
  // Subscribe to layer state changes from StreamService
  createEffect(() => {
    const currentState = streamService.layerState()
    setLayerState(currentState)
  })
  
  // Subscribe to connection state changes from StreamService
  createEffect(() => {
    const currentConnection = streamService.connectionState()
    setConnectionState(currentConnection)
  })
  
  // Utility function to request fresh state
  const requestState = () => {
    streamService.requestState()
  }
  
  return {
    layerState,
    isConnected: () => connectionState().connected,
    connectionState,
    requestState
  }
}