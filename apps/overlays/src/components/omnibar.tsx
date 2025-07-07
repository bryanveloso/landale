import { createEffect, Show } from 'solid-js'
import { useStreamChannel } from '../hooks/use-stream-channel'
import { useLayerOrchestrator } from '../hooks/use-layer-orchestrator'
import { AnimatedLayer } from './animated-layer'
import { LayerRenderer } from './layer-renderer'
import { getLayerForContent, shouldDisplayOnLayer } from '../config/layer-mappings'
import type { ShowType } from '../config/layer-mappings'

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
    const currentShow = state.current_show as ShowType
    
    // Process all content in interrupt stack + active content
    const allContent = [
      ...(state.interrupt_stack || []),
      ...(state.active_content ? [state.active_content] : [])
    ]
    
    // Group content by layer priority
    const layerContent: Record<'foreground' | 'midground' | 'background', any> = {
      foreground: null,
      midground: null,
      background: null
    }
    
    // Assign content to appropriate layers
    allContent.forEach(content => {
      if (content && content.type) {
        const targetLayer = getLayerForContent(content.type, currentShow)
        
        // Only assign if this layer doesn't already have higher priority content
        if (!layerContent[targetLayer] || content.priority > layerContent[targetLayer].priority) {
          layerContent[targetLayer] = content
        }
      }
    })
    
    // Show/hide layers based on content
    Object.keys(layerContent).forEach(layer => {
      const priority = layer as 'foreground' | 'midground' | 'background'
      const content = layerContent[priority]
      
      if (content) {
        orchestrator.showLayer(priority, content)
      } else {
        orchestrator.hideLayer(priority)
      }
    })
  })
  
  // Get content for specific layer
  const getLayerContent = (layer: 'foreground' | 'midground' | 'background') => {
    const state = streamState()
    const currentShow = state.current_show as ShowType
    
    // Find the highest priority content that should display on this layer
    const allContent = [
      ...(state.interrupt_stack || []),
      ...(state.active_content ? [state.active_content] : [])
    ]
    
    return allContent
      .filter(content => content && shouldDisplayOnLayer(content.type, layer, currentShow))
      .sort((a, b) => (b.priority || 0) - (a.priority || 0))[0] || null
  }
  
  const isVisible = () => {
    const state = streamState()
    return state.active_content !== null || (state.interrupt_stack && state.interrupt_stack.length > 0)
  }
  
  return (
    <Show when={isVisible()}>
      <div
        class="w-canvas"
        data-omnibar
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
          <div data-omnibar-debug>
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
          data-connection-status
          data-connected={isConnected()}
        ></div>
      </div>
    </Show>
  )
}
