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

  // Orchestrator methods for debug interface
  showLayer: (priority: LayerPriority, content: unknown) => void
  hideLayer: (priority: LayerPriority) => void
  getLayerState: (priority: LayerPriority) => string
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
    const allContent = [
      ...(state.alerts || []),
      ...(state.current ? [state.current] : []),
      ...(state.base ? [state.base] : [])
    ]

    // Compute content for all layers in a single pass
    const newLayerContents: Record<LayerPriority, LayerContent | null> = {
      foreground: null,
      midground: null,
      background: null
    }

    // Assign content to appropriate layers
    allContent.forEach((content) => {
      if (content && content.type && content.layer && 'data' in content) {
        const targetLayer = content.layer as LayerPriority

        // Skip background assignment for now - we'll handle it separately
        if (targetLayer === 'background') return

        // Only assign if this layer doesn't already have higher priority content
        if (!newLayerContents[targetLayer] || content.priority > newLayerContents[targetLayer]!.priority) {
          newLayerContents[targetLayer] = content as LayerContent
        }
      }
    })

    // Background fallback: show latest event if no background content assigned
    if (!newLayerContents.background) {
      const allowedEventTypes = ['channel.follow', 'channel.subscribe', 'channel.subscription.gift', 'channel.cheer']
      const latestEvent = allContent.find(
        (content) => content && allowedEventTypes.includes(content.type) && 'data' in content
      )
      if (latestEvent) {
        newLayerContents.background = latestEvent as LayerContent
      }
    }

    // Create events timeline for midground if we have events
    if (!newLayerContents.midground && allContent.length > 0) {
      const recentEvents = allContent
        .filter(
          (content) =>
            content &&
            ['channel.follow', 'channel.subscribe', 'channel.subscription.gift', 'channel.cheer'].includes(content.type)
        )
        .slice(0, 6) // Show last 6 events

      if (recentEvents.length > 0) {
        newLayerContents.midground = {
          type: 'events_timeline',
          data: { events: recentEvents },
          priority: 50,
          started_at: new Date().toISOString()
        }
      }
    }

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
    return state.current !== null || (state.alerts && state.alerts.length > 0) || state.base !== null
  })

  // Debug info
  const debug = createMemo(() => {
    if (!import.meta.env.DEV) return null

    const state = streamState()
    return {
      currentContent: state.current?.type || 'none',
      baseContent: state.base?.type || 'none',
      alertsSize: state.alerts?.length || 0,
      tickerSize: state.ticker?.length || 0,
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
    unregisterLayer: orchestrator.unregisterLayer,
    // Expose orchestrator methods for debug interface
    showLayer: orchestrator.showLayer,
    hideLayer: orchestrator.hideLayer,
    getLayerState: orchestrator.getLayerState
  }
}
