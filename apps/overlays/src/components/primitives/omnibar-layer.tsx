import { Show, type JSX, createMemo } from 'solid-js'
import { AnimatedLayer } from '../animated-layer'
import type { LayerPriority } from '../../hooks/use-layer-orchestrator'
import type { LayerContent } from '../../hooks/use-omnibar'

export type OmnibarLayerProps = {
  priority: LayerPriority
  content: () => LayerContent | null
  onRegister: (priority: LayerPriority, element: HTMLElement) => void
  onUnregister: (priority: LayerPriority) => void
  children: (content: LayerContent) => JSX.Element
}

export function OmnibarLayer(props: OmnibarLayerProps) {
  // Memoize the content signal to prevent unnecessary re-evaluations
  const content = createMemo(() => props.content())

  return (
    <AnimatedLayer
      priority={props.priority}
      content={content()}
      contentType={content()?.type}
      onRegister={props.onRegister}
      onUnregister={props.onUnregister}>
      <Show when={content()}>{(c) => props.children(c())}</Show>
    </AnimatedLayer>
  )
}
