import { useLayerState } from '@/hooks/use-layer-state'

export function LayerStateMonitor() {
  const { layerState, isConnected } = useLayerState()

  // Expose for debugging
  if (import.meta.env.DEV) {
    Object.assign(window, { layerState, isConnected })
  }

  const getContentLabel = (content: { type: string } | null) => {
    if (!content) return null
    return content.type.replace(/_/g, ' ')
  }

  return (
    <div>
      {/* Debug info in development */}
      {import.meta.env.DEV && (
        <div>
          <div>Show: {layerState().current_show}</div>
          <div>Version: {layerState().version}</div>
          <div>Updated: {new Date(layerState().last_updated).toLocaleTimeString()}</div>
        </div>
      )}

      {/* Foreground Layer */}
      <div>
        <div>Foreground</div>
        <div></div>
        <div>{getContentLabel(layerState().layers.foreground.content) || '(empty)'}</div>
      </div>

      {/* Midground Layer */}
      <div>
        <div>Midground</div>
        <div></div>
        <div>{getContentLabel(layerState().layers.midground.content) || '(empty)'}</div>
      </div>

      {/* Background Layer */}
      <div>
        <div>Background</div>
        <div></div>
        <div>{getContentLabel(layerState().layers.background.content) || '(empty)'}</div>
      </div>
    </div>
  )
}
