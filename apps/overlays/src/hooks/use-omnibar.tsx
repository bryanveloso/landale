import { createMemo, createEffect, createSignal } from 'solid-js'
import { useStreamChannel } from './use-stream-channel'
import { useLayerOrchestrator } from './use-layer-orchestrator'
import type { LayerPriority } from './use-layer-orchestrator'

export type LayerContent = {
  type: string
  data: unknown
  priority: number
  duration?: number
  started_at: string
  layer?: LayerPriority
}

export type LayerData = {
  content: () => LayerContent | null
  state: () => string
}

export type OmnibarData = {
  // Layer data
  layers: {
    foreground: LayerData
    midground: LayerData
    background: LayerData
  }

  // Visibility
  isVisible: () => boolean

  // Metadata
  currentShow: () => string
  priorityLevel: () => string
  isConnected: () => boolean

  // Debug info (only in dev)
  debug: () => {
    activeContent: string
    stackSize: number
    layerStates: {
      foreground: string
      midground: string
      background: string
    }
  } | null

  // Actions
  registerLayer: (priority: LayerPriority, element: HTMLElement) => void
  unregisterLayer: (priority: LayerPriority) => void
}

export function useOmnibar(): OmnibarData {
  const { streamState, isConnected } = useStreamChannel()
  const orchestrator = useLayerOrchestrator({
    enterDuration: 0.4,
    exitDuration: 0.3,
    interruptDuration: 0.2,
    resumeDuration: 0.4
  })

  // Single signal to store computed layer contents
  const [layerContents, setLayerContents] = createSignal<Record<LayerPriority, LayerContent | null>>({
    foreground: null,
    midground: null,
    background: null
  })

  // Single effect to compute all layer contents and orchestrate visibility
  createEffect(() => {
    const state = streamState()
    const allContent = [...(state.interrupt_stack || []), ...(state.active_content ? [state.active_content] : [])]

    // Compute content for all layers in a single pass
    const newLayerContents: Record<LayerPriority, LayerContent | null> = {
      foreground: null,
      midground: null,
      background: null
    }

    // Assign content to appropriate layers
    allContent.forEach((content) => {
      if (content && content.type && content.layer) {
        const targetLayer = content.layer as LayerPriority

        // Only assign if this layer doesn't already have higher priority content
        if (!newLayerContents[targetLayer] || content.priority > newLayerContents[targetLayer]!.priority) {
          newLayerContents[targetLayer] = content
        }
      }
    })

    // Update the signal with computed contents
    setLayerContents(newLayerContents)

    // Show/hide layers based on content
    Object.keys(newLayerContents).forEach((layer) => {
      const priority = layer as LayerPriority
      const content = newLayerContents[priority]

      if (content) {
        orchestrator.showLayer(priority, content)
      } else {
        orchestrator.hideLayer(priority)
      }
    })
  })

  // Memoized layer states
  const foregroundState = createMemo(() => orchestrator.getLayerState('foreground'))
  const midgroundState = createMemo(() => orchestrator.getLayerState('midground'))
  const backgroundState = createMemo(() => orchestrator.getLayerState('background'))

  // Visibility check
  const isVisible = createMemo(() => {
    const state = streamState()
    return state.active_content !== null || (state.interrupt_stack && state.interrupt_stack.length > 0)
  })

  // Debug info
  const debug = createMemo(() => {
    if (!import.meta.env.DEV) return null

    const state = streamState()
    return {
      activeContent: state.active_content?.type || 'none',
      stackSize: state.interrupt_stack?.length || 0,
      layerStates: {
        foreground: foregroundState(),
        midground: midgroundState(),
        background: backgroundState()
      }
    }
  })

  return {
    layers: {
      foreground: {
        content: () => layerContents().foreground,
        state: foregroundState
      },
      midground: {
        content: () => layerContents().midground,
        state: midgroundState
      },
      background: {
        content: () => layerContents().background,
        state: backgroundState
      }
    },
    isVisible,
    currentShow: () => streamState().current_show,
    priorityLevel: () => streamState().priority_level,
    isConnected,
    debug,
    registerLayer: orchestrator.registerLayer,
    unregisterLayer: orchestrator.unregisterLayer
  }
}
