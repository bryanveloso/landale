import type { Socket } from '@landale/shared/websocket'
import type { LayerPriority } from '../hooks/use-layer-orchestrator'

export interface DebugInterface {
  // Socket operations
  socket: {
    getMetrics: () => unknown
    getState: () => string
    reconnect: () => void
    disconnect: () => void
    connect: () => void
  }

  // Layer orchestration
  layers: {
    showLayer: (priority: LayerPriority, content: unknown) => void
    hideLayer: (priority: LayerPriority) => void
    getState: () => Record<LayerPriority, string>
    simulateFollow: (username: string) => void
    simulateSub: (username: string, months?: number) => void
    simulateRaid: (username: string, viewers: number) => void
    simulateBits: (username: string, amount: number) => void
    clear: () => void
  }

  // Stream state
  stream: {
    getState: () => unknown
    sendEvent: (type: string, data: unknown) => void
  }

  // Utility
  inspect: () => void
  help: () => void
}

export class DebugManager {
  private socket: Socket | null = null
  private orchestratorRef: WeakRef<any> | null = null
  private streamChannelRef: WeakRef<any> | null = null

  setSocket(socket: Socket) {
    this.socket = socket
  }

  setOrchestrator(orchestrator: any) {
    this.orchestratorRef = new WeakRef(orchestrator)
  }

  setStreamChannel(channel: any) {
    this.streamChannelRef = new WeakRef(channel)
  }

  private getOrchestrator() {
    return this.orchestratorRef?.deref()
  }

  private getStreamChannel() {
    return this.streamChannelRef?.deref()
  }

  createInterface(): DebugInterface {
    return {
      socket: {
        getMetrics: () => this.socket?.getHealthMetrics() || null,
        getState: () => this.socket?.getHealthMetrics()?.connectionState || 'unknown',
        reconnect: () => {
          if (this.socket) {
            this.socket.disconnect()
            setTimeout(() => this.socket?.connect(), 100)
          }
        },
        disconnect: () => this.socket?.disconnect(),
        connect: () => this.socket?.connect()
      },

      layers: {
        showLayer: (priority: LayerPriority, content: unknown) => {
          const orchestrator = this.getOrchestrator()
          if (orchestrator) {
            orchestrator.showLayer(priority, content)
            console.log(`✅ Showing ${priority} layer with content:`, content)
          } else {
            console.warn('❌ Orchestrator not available')
          }
        },

        hideLayer: (priority: LayerPriority) => {
          const orchestrator = this.getOrchestrator()
          if (orchestrator) {
            orchestrator.hideLayer(priority)
            console.log(`✅ Hiding ${priority} layer`)
          } else {
            console.warn('❌ Orchestrator not available')
          }
        },

        getState: () => {
          const orchestrator = this.getOrchestrator()
          if (orchestrator) {
            return {
              foreground: orchestrator.getLayerState('foreground'),
              midground: orchestrator.getLayerState('midground'),
              background: orchestrator.getLayerState('background')
            }
          }
          return { foreground: 'unknown', midground: 'unknown', background: 'unknown' }
        },

        simulateFollow: (username: string) => {
          this.sendStreamEvent('follow', {
            username,
            displayName: username,
            timestamp: new Date().toISOString()
          })
        },

        simulateSub: (username: string, months = 1) => {
          this.sendStreamEvent('subscription', {
            username,
            displayName: username,
            months,
            tier: '1000',
            timestamp: new Date().toISOString()
          })
        },

        simulateRaid: (username: string, viewers: number) => {
          this.sendStreamEvent('raid', {
            username,
            displayName: username,
            viewers,
            timestamp: new Date().toISOString()
          })
        },

        simulateBits: (username: string, amount: number) => {
          this.sendStreamEvent('bits', {
            username,
            displayName: username,
            amount,
            timestamp: new Date().toISOString()
          })
        },

        clear: () => {
          const orchestrator = this.getOrchestrator()
          if (orchestrator) {
            ;['foreground', 'midground', 'background'].forEach((priority) => {
              orchestrator.hideLayer(priority as LayerPriority)
            })
            console.log('✅ All layers cleared')
          }
        }
      },

      stream: {
        getState: () => {
          const channel = this.getStreamChannel()
          return channel?.streamState?.() || null
        },

        sendEvent: (type: string, data: unknown) => {
          this.sendStreamEvent(type, data)
        }
      },

      inspect: () => {
        console.group('🔍 Landale Debug State')

        console.group('Socket')
        console.log('State:', this.socket?.getHealthMetrics()?.connectionState)
        console.log('Metrics:', this.socket?.getHealthMetrics())
        console.groupEnd()

        console.group('Layers')
        const orchestrator = this.getOrchestrator()
        if (orchestrator) {
          console.log('States:', {
            foreground: orchestrator.getLayerState('foreground'),
            midground: orchestrator.getLayerState('midground'),
            background: orchestrator.getLayerState('background')
          })
        }
        console.groupEnd()

        console.group('Stream')
        const channel = this.getStreamChannel()
        console.log('State:', channel?.streamState?.())
        console.groupEnd()

        console.groupEnd()
      },

      help: () => {
        console.log(`
🎮 Landale Debug Interface

Socket Operations:
  debug.socket.getMetrics()    - View connection health metrics
  debug.socket.getState()      - Get current connection state
  debug.socket.reconnect()     - Force reconnect
  debug.socket.disconnect()    - Disconnect from server
  debug.socket.connect()       - Connect to server

Layer Control:
  debug.layers.showLayer(priority, content)  - Show content on a layer
  debug.layers.hideLayer(priority)          - Hide a layer
  debug.layers.getState()                   - Get all layer states
  debug.layers.clear()                      - Clear all layers

Simulate Events:
  debug.layers.simulateFollow(username)           - Simulate follow
  debug.layers.simulateSub(username, months?)     - Simulate subscription
  debug.layers.simulateRaid(username, viewers)    - Simulate raid
  debug.layers.simulateBits(username, amount)     - Simulate bits

Stream Control:
  debug.stream.getState()              - Get current stream state
  debug.stream.sendEvent(type, data)   - Send custom event

Utilities:
  debug.inspect()  - Inspect full state
  debug.help()     - Show this help

Query Parameters:
  ?debug=true      - Enable debug mode
  ?debug=follow    - Auto-simulate follow on load
  ?debug=sub       - Auto-simulate subscription on load
  ?debug=raid      - Auto-simulate raid on load

Examples:
  debug.layers.showLayer('foreground', { type: 'test', data: 'Hello!' })
  debug.layers.simulateFollow('testuser123')
  debug.inspect()
        `)
      }
    }
  }

  private sendStreamEvent(type: string, data: unknown) {
    const channel = this.getStreamChannel()
    if (channel?.channel) {
      channel.channel.push('debug:event', { type, data })
      console.log(`✅ Sent ${type} event:`, data)
    } else {
      console.warn('❌ Stream channel not available')
    }
  }
}

// Global instance
export const debugManager = new DebugManager()
