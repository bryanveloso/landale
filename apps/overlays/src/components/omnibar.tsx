import { For, Show } from 'solid-js'
import { useOmnibar } from '../hooks/use-omnibar'
import { OmnibarRoot } from './primitives/omnibar-root'
import { OmnibarLayer } from './primitives/omnibar-layer'
import { OmnibarDebug } from './primitives/omnibar-debug'
import { ConnectionIndicator } from './primitives/connection-indicator'
import { LayerRenderer } from './layer-renderer'
import type { LayerPriority } from '../hooks/use-layer-orchestrator'

/**
 * Omnibar component with all logic abstracted into hooks.
 * This component is purely presentational - all business logic
 * is handled by useOmnibar hook.
 */
export function Omnibar() {
  const omnibar = useOmnibar()

  // Define layer order for rendering
  const layerOrder: LayerPriority[] = ['foreground', 'midground', 'background']

  return (
    <OmnibarRoot
      show={omnibar.isVisible}
      rootProps={{
        class: 'omnibar w-canvas',
        'data-show': omnibar.currentShow(),
        'data-priority': omnibar.priorityLevel(),
        'data-connected': omnibar.isConnected()
      }}>
      {/* Render all layers in order */}
      <For each={layerOrder}>
        {(layerName) => (
          <OmnibarLayer
            priority={layerName}
            content={omnibar.layers[layerName].content}
            onRegister={omnibar.registerLayer}
            onUnregister={omnibar.unregisterLayer}>
            {(content) => <LayerRenderer content={content} contentType={content.type} show={omnibar.currentShow()} />}
          </OmnibarLayer>
        )}
      </For>

      {/* Debug panel (dev only) */}
      <Show when={omnibar.debug()}>{(debug) => <OmnibarDebug {...debug()} />}</Show>

      {/* Connection indicator */}
      <ConnectionIndicator connected={omnibar.isConnected} />
    </OmnibarRoot>
  )
}
