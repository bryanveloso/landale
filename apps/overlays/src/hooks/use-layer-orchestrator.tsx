import { createSignal, onCleanup } from 'solid-js'
import { gsap } from 'gsap'

export type LayerPriority = 'foreground' | 'midground' | 'background'
export type LayerState = 'hidden' | 'entering' | 'active' | 'interrupted' | 'exiting'

export interface LayerConfig {
  priority: LayerPriority
  element: HTMLElement | null
  state: LayerState
  content: unknown
}

export interface AnimationConfig {
  enterDuration: number
  exitDuration: number
  interruptDuration: number
  resumeDuration: number
}

const DEFAULT_ANIMATION_CONFIG: AnimationConfig = {
  enterDuration: 0.4,
  exitDuration: 0.3,
  interruptDuration: 0.2,
  resumeDuration: 0.4
}

export function useLayerOrchestrator(config: Partial<AnimationConfig> = {}) {
  const animConfig = { ...DEFAULT_ANIMATION_CONFIG, ...config }
  
  // Create GSAP context for managing all animations
  const ctx = gsap.context(() => {})
  
  // Clean up all animations when hook is disposed
  onCleanup(() => {
    // Clean up individual layer contexts first
    Object.values(layerContexts).forEach(layerCtx => {
      if (layerCtx) {
        layerCtx.revert()
      }
    })
    
    // Clean up main context
    ctx.revert()
  })
  
  // Track layer states
  const [layerStates, setLayerStates] = createSignal<Record<LayerPriority, LayerState>>({
    foreground: 'hidden',
    midground: 'hidden',
    background: 'hidden'
  })
  
  // Track layer elements for animation
  const layerElements: Record<LayerPriority, HTMLElement | null> = {
    foreground: null,
    midground: null,
    background: null
  }
  
  // Track per-layer animation contexts for interruption handling
  const layerContexts: Record<LayerPriority, gsap.Context | null> = {
    foreground: null,
    midground: null,
    background: null
  }
  
  // Queue for pending state changes before registration
  const pendingStateChanges: Record<LayerPriority, { state: LayerState; content: unknown } | null> = {
    foreground: null,
    midground: null,
    background: null
  }
  
  // Register a layer element for animation
  const registerLayer = (priority: LayerPriority, element: HTMLElement) => {
    layerElements[priority] = element
    
    // Create per-layer context for animation management
    layerContexts[priority] = gsap.context(() => {}, element)
    
    // Set initial state
    ctx.add(() => {
      gsap.set(element, {
        opacity: 0,
        y: 20,
        scale: 0.95
      })
    })
    
    // Sync DOM attribute with current internal state
    const currentState = layerStates()[priority]
    element.setAttribute('data-state', currentState)
    
    // Process any pending state changes for this layer
    const pending = pendingStateChanges[priority]
    if (pending) {
      pendingStateChanges[priority] = null
      updateLayerState(priority, pending.state)
    }
  }
  
  // Update layer state and trigger appropriate animation
  const updateLayerState = (priority: LayerPriority, newState: LayerState, content?: unknown) => {
    setLayerStates(prev => ({
      ...prev,
      [priority]: newState
    }))
    
    const element = layerElements[priority]
    if (!element) {
      // Queue state change for when layer gets registered
      pendingStateChanges[priority] = { state: newState, content }
      return
    }
    
    // Update data attribute for CSS styling hooks
    element.setAttribute('data-state', newState)
    
    // Kill any existing animations for this layer before starting new ones
    const layerCtx = layerContexts[priority]
    if (layerCtx) {
      layerCtx.revert()
    }
    
    switch (newState) {
      case 'entering':
        animateEnter(element, priority)
        break
      case 'exiting':
        animateExit(element, priority)
        break
      case 'interrupted':
        animateInterrupt(element, priority)
        break
      case 'active':
        animateResume(element, priority)
        break
    }
  }
  
  // Animation functions using GSAP
  const animateEnter = (element: HTMLElement, priority: LayerPriority) => {
    const layerCtx = layerContexts[priority]
    if (!layerCtx) return
    
    layerCtx.add(() => {
      const timeline = gsap.timeline({
        onComplete: () => updateLayerState(priority, 'active')
      })
      
      timeline.to(element, {
        opacity: 1,
        y: 0,
        scale: 1,
        duration: animConfig.enterDuration,
        ease: "power2.out"
      })
    })
    
    // Handle layer stacking during enter
    handleLayerStacking(priority)
  }
  
  const animateExit = (element: HTMLElement, priority: LayerPriority) => {
    const layerCtx = layerContexts[priority]
    if (!layerCtx) return
    
    layerCtx.add(() => {
      const timeline = gsap.timeline({
        onComplete: () => updateLayerState(priority, 'hidden')
      })
      
      timeline.to(element, {
        opacity: 0,
        y: -20,
        scale: 0.95,
        duration: animConfig.exitDuration,
        ease: "power2.in"
      })
    })
    
    // Restore lower priority layers after exit
    restoreLowerPriorityLayers(priority)
  }
  
  const animateInterrupt = (element: HTMLElement, priority: LayerPriority) => {
    const layerCtx = layerContexts[priority]
    if (!layerCtx) return
    
    layerCtx.add(() => {
      gsap.to(element, {
        y: getPushDistance(priority),
        scale: getInterruptedScale(priority),
        opacity: getInterruptedOpacity(priority),
        duration: animConfig.interruptDuration,
        ease: "power2.out"
      })
    })
  }
  
  const animateResume = (element: HTMLElement, priority: LayerPriority) => {
    const layerCtx = layerContexts[priority]
    if (!layerCtx) return
    
    layerCtx.add(() => {
      gsap.to(element, {
        y: 0,
        scale: 1,
        opacity: 1,
        duration: animConfig.resumeDuration,
        ease: "power2.out"
      })
    })
  }
  
  // Handle layer stacking when higher priority content appears
  const handleLayerStacking = (incomingPriority: LayerPriority) => {
    const priorities: LayerPriority[] = ['foreground', 'midground', 'background']
    const incomingIndex = priorities.indexOf(incomingPriority)
    
    // Interrupt all lower priority layers
    priorities.slice(incomingIndex + 1).forEach(layerPriority => {
      const currentState = layerStates()[layerPriority]
      if (currentState === 'active' || currentState === 'entering') {
        updateLayerState(layerPriority, 'interrupted')
      }
    })
  }
  
  // Restore lower priority layers when higher priority exits
  const restoreLowerPriorityLayers = (exitingPriority: LayerPriority) => {
    const priorities: LayerPriority[] = ['foreground', 'midground', 'background']
    const exitingIndex = priorities.indexOf(exitingPriority)
    
    // Find the highest priority layer that should now be active
    for (let i = exitingIndex + 1; i < priorities.length; i++) {
      const layerPriority = priorities[i]
      const currentState = layerStates()[layerPriority]
      
      if (currentState === 'interrupted' && layerElements[layerPriority]) {
        updateLayerState(layerPriority, 'active')
        break // Only restore the highest priority interrupted layer
      }
    }
  }
  
  // Helper functions for interrupted layer styling
  const getPushDistance = (priority: LayerPriority): number => {
    switch (priority) {
      case 'midground': return 30
      case 'background': return 60
      default: return 0
    }
  }
  
  const getInterruptedScale = (priority: LayerPriority): number => {
    switch (priority) {
      case 'midground': return 0.95
      case 'background': return 0.9
      default: return 1
    }
  }
  
  const getInterruptedOpacity = (priority: LayerPriority): number => {
    switch (priority) {
      case 'midground': return 0.7
      case 'background': return 0.5
      default: return 1
    }
  }
  
  // Public API for showing/hiding layers
  const showLayer = (priority: LayerPriority, content: unknown) => {
    const currentState = layerStates()[priority]
    
    if (currentState === 'hidden') {
      updateLayerState(priority, 'entering', content)
    } else if (currentState === 'interrupted') {
      // If layer was interrupted and now should be active
      updateLayerState(priority, 'active', content)
    }
  }
  
  const hideLayer = (priority: LayerPriority) => {
    const currentState = layerStates()[priority]
    
    if (currentState === 'active' || currentState === 'interrupted' || currentState === 'entering') {
      updateLayerState(priority, 'exiting')
    }
  }
  
  const isLayerVisible = (priority: LayerPriority): boolean => {
    const state = layerStates()[priority]
    return state !== 'hidden' && state !== 'exiting'
  }
  
  const getLayerState = (priority: LayerPriority): LayerState => {
    return layerStates()[priority]
  }
  
  // Unregister a layer and clean up its animations
  const unregisterLayer = (priority: LayerPriority) => {
    const layerCtx = layerContexts[priority]
    if (layerCtx) {
      layerCtx.revert()
      layerContexts[priority] = null
    }
    
    layerElements[priority] = null
    pendingStateChanges[priority] = null
    
    // Reset state
    setLayerStates(prev => ({
      ...prev,
      [priority]: 'hidden'
    }))
  }

  return {
    registerLayer,
    unregisterLayer,
    showLayer,
    hideLayer,
    isLayerVisible,
    getLayerState,
    layerStates: layerStates()
  }
}
