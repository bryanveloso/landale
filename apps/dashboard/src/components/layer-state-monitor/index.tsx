import { useLayerState } from '../../hooks/use-layer-state'

export function LayerStateMonitor() {
  const { layerState, isConnected } = useLayerState()

  // Expose for debugging
  if (import.meta.env.DEV) {
    window.layerState = layerState
    window.isConnected = isConnected
  }
  
  const getContentLabel = (content: any) => {
    if (!content) return null
    return content.type.replace(/_/g, ' ')
  }
  
  return (
    <div
      data-layer-monitor
      data-show={layerState().current_show}
      data-connected={isConnected()}
    >
      {/* Debug info in development */}
      {import.meta.env.DEV && (
        <div data-debug-info>
          <div>Connected: {isConnected() ? '✓' : '✗'}</div>
          <div>Show: {layerState().current_show}</div>
          <div>Version: {layerState().version}</div>
          <div>Updated: {new Date(layerState().last_updated).toLocaleTimeString()}</div>
        </div>
      )}
      {/* Foreground Layer */}
      <div 
        data-layer="foreground"
        data-active={layerState().layers.foreground.content !== null}
      >
        <div data-layer-name>Foreground</div>
        <div data-layer-indicator data-active={layerState().layers.foreground.content !== null}></div>
        <div data-layer-content>
          {getContentLabel(layerState().layers.foreground.content) || '(empty)'}
        </div>
      </div>
      
      {/* Midground Layer */}
      <div 
        data-layer="midground"
        data-active={layerState().layers.midground.content !== null}
      >
        <div data-layer-name>Midground</div>
        <div data-layer-indicator data-active={layerState().layers.midground.content !== null}></div>
        <div data-layer-content>
          {getContentLabel(layerState().layers.midground.content) || '(empty)'}
        </div>
      </div>
      
      {/* Background Layer */}
      <div 
        data-layer="background"
        data-active={layerState().layers.background.content !== null}
      >
        <div data-layer-name>Background</div>
        <div data-layer-indicator data-active={layerState().layers.background.content !== null}></div>
        <div data-layer-content>
          {getContentLabel(layerState().layers.background.content) || '(empty)'}
        </div>
      </div>
    </div>
  )
}