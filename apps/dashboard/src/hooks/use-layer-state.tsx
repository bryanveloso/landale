import { createSignal, createEffect, onCleanup } from 'solid-js'
import { Channel } from 'phoenix'
import { useSocket } from '../providers/socket-provider'

export interface LayerContent {
  type: string
  data: any
  priority: number
  duration?: number
  started_at: string
}

export interface LayerState {
  priority: 'foreground' | 'midground' | 'background'
  state: 'hidden' | 'entering' | 'active' | 'interrupted' | 'exiting'
  content: LayerContent | null
  animation_progress?: number
}

export interface OverlayLayerState {
  current_show: 'ironmon' | 'variety' | 'coding'
  layers: {
    foreground: LayerState
    midground: LayerState
    background: LayerState
  }
  active_content: LayerContent | null
  interrupt_stack: LayerContent[]
  priority_level: 'alert' | 'sub_train' | 'ticker'
  version: number
  last_updated: string
}

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
  const { socket, isConnected } = useSocket()
  const [layerState, setLayerState] = createSignal<OverlayLayerState>(DEFAULT_LAYER_STATE)
  
  let channel: Channel | null = null
  
  const joinChannel = () => {
    const currentSocket = socket()
    if (!currentSocket) return
    
    // Join the stream overlays channel to monitor layer states
    channel = currentSocket.channel('stream:overlays', {})
    
    // Handle stream state updates
    channel.on('stream_state', (payload: any) => {
      console.log('[LayerState] Received stream state:', payload)
      
      // Transform server state to layer-focused state
      const transformedState = transformServerState(payload)
      setLayerState(transformedState)
    })
    
    // Handle show changes
    channel.on('show_changed', (payload: any) => {
      console.log('[LayerState] Show changed:', payload)
      setLayerState(prev => ({
        ...prev,
        current_show: payload.show,
        last_updated: payload.changed_at
      }))
    })
    
    // Handle individual interrupt events
    channel.on('interrupt', (payload: any) => {
      console.log('[LayerState] Priority interrupt:', payload)
      // The stream_state update will handle the actual layer changes
    })
    
    // Handle real-time content updates
    channel.on('content_update', (payload: any) => {
      console.log('[LayerState] Content update:', payload)
      // Update specific layer content without full state refresh
      setLayerState(prev => updateLayerContent(prev, payload))
    })
    
    // Join channel with error handling
    channel.join()
      .receive('ok', (resp: any) => {
        console.log('[LayerState] Successfully joined stream channel', resp)
        // Request initial state
        channel?.push('request_state', {})
      })
      .receive('error', (resp: any) => {
        console.error('[LayerState] Unable to join stream channel', resp)
      })
      .receive('timeout', () => {
        console.error('[LayerState] Stream channel join timeout')
      })
  }
  
  const leaveChannel = () => {
    if (channel) {
      channel.leave()
      channel = null
    }
  }
  
  // Transform server StreamProducer state to layer-focused state
  const transformServerState = (serverState: any): OverlayLayerState => {
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
      current_show: serverState.current_show || 'variety',
      layers,
      active_content: serverState.active_content,
      interrupt_stack: serverState.interrupt_stack || [],
      priority_level: serverState.priority_level || 'ticker',
      version: serverState.metadata?.state_version || serverState.version || 0,
      last_updated: serverState.metadata?.last_updated || new Date().toISOString()
    }
  }
  
  // Extract content for specific layer based on show context
  const extractLayerContent = (allContent: any[], targetLayer: 'foreground' | 'midground' | 'background', show: string): LayerState => {
    // Simple layer assignment logic (matches the overlay system)
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
    }
  }
  
  // Update specific layer content from real-time updates
  const updateLayerContent = (currentState: OverlayLayerState, update: any): OverlayLayerState => {
    // This would handle real-time updates like emote increments
    // For now, just return current state - full implementation would
    // update specific content data without disrupting layer states
    return currentState
  }
  
  // Watch for socket connection changes
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
    layerState,
    isConnected
  }
}