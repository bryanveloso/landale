import { createEffect, createMemo, Show } from 'solid-js'
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

  // Unregister layer callback
  const handleLayerUnregister = (priority: 'foreground' | 'midground' | 'background') => {
    orchestrator.unregisterLayer(priority)
  }

  // Memoized layer content to prevent redundant calculations
  const foregroundContent = createMemo(() => getLayerContent('foreground'))
  const midgroundContent = createMemo(() => getLayerContent('midground'))
  const backgroundContent = createMemo(() => getLayerContent('background'))

  // React to stream state changes and orchestrate layer visibility
  createEffect(() => {
    const state = streamState()

    // Process all content in interrupt stack + active content
    const allContent = [...(state.interrupt_stack || []), ...(state.active_content ? [state.active_content] : [])]

    // Group content by layer priority
    const layerContent: Record<'foreground' | 'midground' | 'background', unknown> = {
      foreground: null,
      midground: null,
      background: null
    }

    // Assign content to appropriate layers using server-provided layer field
    allContent.forEach((content) => {
      if (content && content.type && content.layer) {
        const targetLayer = content.layer as 'foreground' | 'midground' | 'background'

        // Only assign if this layer doesn't already have higher priority content
        if (!layerContent[targetLayer] || content.priority > layerContent[targetLayer].priority) {
          layerContent[targetLayer] = content
        }
      }
    })

    // Show/hide layers based on content
    Object.keys(layerContent).forEach((layer) => {
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

    // Find the highest priority content that should display on this layer
    const allContent = [...(state.interrupt_stack || []), ...(state.active_content ? [state.active_content] : [])]

    return (
      allContent
        .filter((content) => content && content.layer === layer)
        .sort((a, b) => (b.priority || 0) - (a.priority || 0))[0] || null
    )
  }

  const isVisible = () => {
    const state = streamState()
    return state.active_content !== null || (state.interrupt_stack && state.interrupt_stack.length > 0)
  }

  return (
    <Show when={isVisible()}>
      <div
        class="w-canvas"
        class="omnibar"
        data-show={streamState().current_show}
        data-priority={streamState().priority_level}
        data-connected={isConnected()}>
        {/* Foreground Layer - Highest priority alerts */}
        <AnimatedLayer
          priority="foreground"
          content={foregroundContent()}
          contentType={foregroundContent()?.type}
          show={streamState().current_show}
          onRegister={handleLayerRegister}
          onUnregister={handleLayerUnregister}>
          <Show when={foregroundContent()}>
            <LayerRenderer
              content={foregroundContent()}
              contentType={foregroundContent()?.type || ''}
              show={streamState().current_show}
            />
          </Show>
        </AnimatedLayer>

        {/* Midground Layer - Sub trains, celebrations */}
        <AnimatedLayer
          priority="midground"
          content={midgroundContent()}
          contentType={midgroundContent()?.type}
          show={streamState().current_show}
          onRegister={handleLayerRegister}
          onUnregister={handleLayerUnregister}>
          <Show when={midgroundContent()}>
            <LayerRenderer
              content={midgroundContent()}
              contentType={midgroundContent()?.type || ''}
              show={streamState().current_show}
            />
          </Show>
        </AnimatedLayer>

        {/* Background Layer - Ticker content, stats */}
        <AnimatedLayer
          priority="background"
          content={backgroundContent()}
          contentType={backgroundContent()?.type}
          show={streamState().current_show}
          onRegister={handleLayerRegister}
          onUnregister={handleLayerUnregister}>
          <Show when={backgroundContent()}>
            <LayerRenderer
              content={backgroundContent()}
              contentType={backgroundContent()?.type || ''}
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
        <div class="connection-status" data-connected={isConnected()}></div>
      </div>
    </Show>
  )
}
