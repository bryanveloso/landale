import { createEffect, onMount, createSignal, type Component, type JSX } from 'solid-js'
import { Socket } from 'phoenix'
import { createPhoenixSocket } from '@landale/shared/phoenix-connection'
import { debugManager } from '../debug/debug-interface'
import { createLogger } from '@landale/logger/browser'

interface DebugProviderProps {
  children: JSX.Element
  orchestrator?: {
    showLayer: (priority: string, content: unknown) => void
    hideLayer: (priority: string) => void
    clearAllLayers: () => void
    getLayerStates: () => Record<string, string>
  }
  streamChannel?: { push: (event: string, payload: unknown) => void }
}

export const DebugProvider: Component<DebugProviderProps> = (props) => {
  const [, setSocket] = createSignal<Socket | null>(null)
  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'debug-provider' })

  onMount(() => {
    // Create Phoenix socket for debug
    const phoenixSocket = createPhoenixSocket()
    setSocket(phoenixSocket)

    // Set up debug manager references
    if (phoenixSocket) {
      debugManager.setSocket(phoenixSocket)
    }
  })

  createEffect(() => {
    if (props.orchestrator) {
      debugManager.setOrchestrator(props.orchestrator)
    }
  })

  createEffect(() => {
    if (props.streamChannel) {
      debugManager.setStreamChannel(props.streamChannel)
    }
  })

  onMount(() => {
    // Only enable in development or with debug query param
    const urlParams = new URLSearchParams(window.location.search)
    const debugParam = urlParams.get('debug')
    const isDev = import.meta.env.DEV

    if (isDev || debugParam) {
      // Create debug interface
      const debug = debugManager.createInterface()
      ;(window as Window & { debug?: typeof debug }).debug = debug

      logger.info('Debug interface enabled', {
        metadata: {
          development: isDev,
          debugParam: !!debugParam
        }
      })

      // Log initial state
      logger.debug('Debug provider mounted', {
        metadata: {
          hasOrchestrator: !!props.orchestrator,
          hasStreamChannel: !!props.streamChannel
        }
      })

      // Add help text
      console.log('%c🛠️ Debug Interface Ready', 'font-size: 14px; font-weight: bold; color: #4ade80;')
      console.log('Type `debug.help()` to see available commands')
    }
  })

  return <>{props.children}</>
}
