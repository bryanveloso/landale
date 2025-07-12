import { createEffect, createMemo, Show } from 'solid-js'
import { useStreamChannel } from '../hooks/use-stream-channel'
import { useLayerOrchestrator } from '../hooks/use-layer-orchestrator'
import { AnimatedLayer } from './animated-layer'
import { LayerRenderer } from './layer-renderer'
import { LayerResolver, PerformanceMonitor, type ShowType, type StreamContent } from '@landale/shared'
import { OverlayErrorBoundary } from './error-boundary'
import { ConnectionErrorBoundary } from './connection-error-boundary'

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
  
  // React to memoized layer distribution changes
  createEffect(() => {
    PerformanceMonitor.trackRenderCycle()
    const distribution = layerDistribution()
    
    // Show/hide layers based on distributed content
    Object.entries(distribution).forEach(([layer, layerState]) => {
      const priority = layer as 'foreground' | 'midground' | 'background'
      
      if (layerState.content) {
        orchestrator.showLayer(priority, layerState.content)
      } else {
        orchestrator.hideLayer(priority)
      }
    })
  })
  
  // Memoized content preparation to avoid repeated computation
  const allContent = createMemo((): StreamContent[] => {
    const state = streamState()
    const rawContent = [
      ...(state.interrupt_stack || []),
      ...(state.active_content ? [state.active_content] : [])
    ].filter(item => 
      item != null && 
      typeof item === 'object' && 
      'type' in item && 
      typeof item.priority === 'number'
    )
    
    // Convert to StreamContent interface
    return rawContent as StreamContent[]
  })

  const currentShow = createMemo(() => {
    return (streamState().current_show as ShowType) || 'variety'
  })

  // Memoized layer distribution to avoid recalculating on every access
  const layerDistribution = createMemo(() => {
    return LayerResolver.distributeContent(allContent(), currentShow())
  })

  // Get content for specific layer using memoized distribution
  const getLayerContent = (layer: 'foreground' | 'midground' | 'background') => {
    return layerDistribution()[layer].content
  }
  
  const isVisible = createMemo(() => {
    const state = streamState()
    return state.active_content !== null || (state.interrupt_stack && state.interrupt_stack.length > 0)
  })
  
  return (
    <ConnectionErrorBoundary>
      <Show when={isVisible()}>
        <div
          class="w-canvas"
          data-omnibar
          data-show={streamState().current_show}
          data-priority={streamState().priority_level}
          data-connected={isConnected()}
        >
        {/* Foreground Layer - Highest priority alerts */}
        <OverlayErrorBoundary layerName="foreground">
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
        </OverlayErrorBoundary>
        
        {/* Midground Layer - Sub trains, celebrations */}
        <OverlayErrorBoundary layerName="midground">
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
        </OverlayErrorBoundary>
        
        {/* Background Layer - Ticker content, stats */}
        <OverlayErrorBoundary layerName="background">
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
        </OverlayErrorBoundary>
        
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
    </ConnectionErrorBoundary>
  )
}
