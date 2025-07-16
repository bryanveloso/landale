import { createEffect, onMount, type JSX } from 'solid-js'
import type { LayerPriority } from '../hooks/use-layer-orchestrator'

export interface AnimatedLayerProps {
  priority: LayerPriority
  content: unknown
  contentType?: string
  show?: string
  onRegister?: (priority: LayerPriority, element: HTMLElement) => void
  children?: JSX.Element
}

export function AnimatedLayer(props: AnimatedLayerProps) {
  let layerRef: HTMLDivElement | undefined
  
  // Register this layer with the orchestrator on mount
  onMount(() => {
    if (props.onRegister && layerRef) {
      props.onRegister(props.priority, layerRef)
    }
  })
  
  // Update data attributes when content changes
  createEffect(() => {
    if (layerRef) {
      // Core layer attributes
      layerRef.setAttribute('data-layer', props.priority)
      layerRef.setAttribute('data-priority', getPriorityNumber(props.priority).toString())
      
      // Content-specific attributes
      if (props.contentType) {
        layerRef.setAttribute('data-content-type', props.contentType)
      }
      
      // Show-specific attributes
      if (props.show) {
        layerRef.setAttribute('data-show', props.show)
      }
      
      // Content presence
      layerRef.setAttribute('data-has-content', (props.content !== null && props.content !== undefined).toString())
    }
  })
  
  return (
    <div 
      ref={layerRef}
      data-layer={props.priority}
      data-priority={getPriorityNumber(props.priority)}
      data-state="hidden"
      data-has-content={props.content !== null && props.content !== undefined}
    >
      {props.children}
    </div>
  )
}

// Helper function to get numeric priority for CSS ordering
function getPriorityNumber(priority: LayerPriority): number {
  switch (priority) {
    case 'foreground': return 100
    case 'midground': return 50
    case 'background': return 10
    default: return 0
  }
}