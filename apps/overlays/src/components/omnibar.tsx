import { createEffect, Show } from 'solid-js'
import { useStreamChannel } from '../hooks/use-stream-channel'
import { useLayerOrchestrator } from '../hooks/use-layer-orchestrator'
import { AnimatedLayer } from './animated-layer'
import { LayerRenderer } from './layer-renderer'

export function Omnibar() {
  const { streamState, isConnected } = useStreamChannel()
  const orchestrator = useLayerOrchestrator({
    enterDuration: 0.4,
    exitDuration: 0.3,
    interruptDuration: 0.2,
    resumeDuration: 0.4
  })
  
  // Register layer callback
  const handleLayerRegister = (priority: 'foreground' | 'midground' | 'background', element: HTMLElement) => {
    orchestrator.registerLayer(priority, element)
  }
  
  // React to stream state changes and orchestrate layer visibility
  createEffect(() => {
    const state = streamState()
    const layerAssignments = state.layer_assignments
    
    // Show/hide layers based on server assignments
    if (layerAssignments?.foreground) {
      orchestrator.showLayer('foreground', layerAssignments.foreground)
    } else {
      orchestrator.hideLayer('foreground')
    }
    
    if (layerAssignments?.midground) {
      orchestrator.showLayer('midground', layerAssignments.midground)
    } else {
      orchestrator.hideLayer('midground')
    }
    
    if (layerAssignments?.background) {
      orchestrator.showLayer('background', layerAssignments.background)
    } else {
      orchestrator.hideLayer('background')
    }
  })
  
  // Get content for specific layer from server assignments
  const getLayerContent = (layer: 'foreground' | 'midground' | 'background') => {
    const state = streamState()
    return state.layer_assignments?.[layer] || null
  }
  
  const isVisible = () => {
    const state = streamState()
    return state.active_content !== null || (state.interrupt_stack && state.interrupt_stack.length > 0)
  }
  
  return (
    <Show when={isVisible()}>
      <div
        class="w-canvas omnibar"
        data-show={streamState().current_show}
        data-priority={streamState().priority_level}
        data-connected={isConnected()}
      >
        {/* Foreground Layer - Highest priority alerts */}
        <AnimatedLayer
          priority="foreground"
          content={getLayerContent('foreground')}
          contentType={getLayerContent('foreground')?.type}
          show={streamState().current_show}
          onRegister={handleLayerRegister}
        >
          <Show when={getLayerContent('foreground')}>
            <LayerRenderer
              content={getLayerContent('foreground')}
              contentType={getLayerContent('foreground')?.type || ''}
              show={streamState().current_show}
            />
          </Show>
        </AnimatedLayer>
        
        {/* Midground Layer - Sub trains, celebrations */}
        <AnimatedLayer
          priority="midground"
          content={getLayerContent('midground')}
          contentType={getLayerContent('midground')?.type}
          show={streamState().current_show}
          onRegister={handleLayerRegister}
        >
          <Show when={getLayerContent('midground')}>
            <LayerRenderer
              content={getLayerContent('midground')}
              contentType={getLayerContent('midground')?.type || ''}
              show={streamState().current_show}
            />
          </Show>
        </AnimatedLayer>
        
        {/* Background Layer - Ticker content, stats */}
        <AnimatedLayer
          priority="background"
          content={getLayerContent('background')}
          contentType={getLayerContent('background')?.type}
          show={streamState().current_show}
          onRegister={handleLayerRegister}
        >
          <Show when={getLayerContent('background')}>
            <LayerRenderer
              content={getLayerContent('background')}
              contentType={getLayerContent('background')?.type || ''}
              show={streamState().current_show}
            />
          </Show>
        </AnimatedLayer>
        
        {/* Debug info - only in development */}
        {import.meta.env.DEV && (
          <div class="omnibar-debug">
            <div>Show: {streamState().current_show}</div>
            <div>Priority: {streamState().priority_level}</div>
            <div>Foreground: {orchestrator.getLayerState('foreground')}</div>
            <div>Midground: {orchestrator.getLayerState('midground')}</div>
            <div>Background: {orchestrator.getLayerState('background')}</div>
            <div>Active: {streamState().active_content?.type || 'none'}</div>
            <div>Stack: {streamState().interrupt_stack?.length || 0}</div>
          </div>
        )}
        
        {/* Connection status indicator */}
        <div 
          class="connection-status"
          data-connected={isConnected()}
        ></div>
      </div>
    </Show>
  )
}
