import { createEffect, onMount, type Component, type JSX } from 'solid-js'
import { useSocket } from './socket-provider'
import { debugManager } from '../debug/debug-interface'
import { createLogger } from '@landale/logger/browser'

interface DebugProviderProps {
  children: JSX.Element
  orchestrator?: any
  streamChannel?: any
}

export const DebugProvider: Component<DebugProviderProps> = (props) => {
  const { socket } = useSocket()
  const logger = createLogger({
    service: 'landale-overlays',
    level: 'debug'
  }).child({ module: 'debug-provider' })

  // Set up debug manager references
  createEffect(() => {
    const currentSocket = socket()
    if (currentSocket) {
      debugManager.setSocket(currentSocket)
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
      ;(window as any).debug = debug

      logger.info('Debug interface enabled', {
        metadata: { isDev, debugParam }
      })

      // Show help on first load
      if (!sessionStorage.getItem('landale-debug-shown')) {
        console.log('🎮 Landale Debug Interface enabled! Type `debug.help()` for commands.')
        sessionStorage.setItem('landale-debug-shown', 'true')
      }

      // Handle auto-simulation based on query param
      if (debugParam && debugParam !== 'true') {
        setTimeout(() => {
          switch (debugParam) {
            case 'follow':
              debug.layers.simulateFollow('debuguser')
              break
            case 'sub':
              debug.layers.simulateSub('debuguser', 3)
              break
            case 'raid':
              debug.layers.simulateRaid('debugraider', 100)
              break
            case 'bits':
              debug.layers.simulateBits('debugbits', 500)
              break
            case 'inspect':
              debug.inspect()
              break
          }
        }, 2000) // Wait for everything to initialize
      }

      // Listen for keyboard shortcuts in debug mode
      window.addEventListener('keydown', (e) => {
        // Ctrl/Cmd + Shift + D to toggle debug panel
        if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'D') {
          e.preventDefault()
          debug.inspect()
        }

        // Ctrl/Cmd + Shift + C to clear all layers
        if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'C') {
          e.preventDefault()
          debug.layers.clear()
        }
      })
    }
  })

  return <>{props.children}</>
}
