import type { EventEmitter } from '@/events/emitter'
import type { StatusBarConfig, StatusBarState } from '@/types/control'
import { statusBarConfigSchema } from '@/types/control'
import { logger } from '@/lib/logger'

export class StatusBarService {
  private state: StatusBarState
  private readonly eventEmitter: EventEmitter

  constructor(eventEmitter: EventEmitter) {
    this.eventEmitter = eventEmitter
    
    // Initialize with default state
    this.state = {
      mode: 'preshow',
      text: undefined,
      isVisible: true,
      position: 'bottom',
      lastUpdated: new Date().toISOString()
    }

    logger.info('[StatusBar] Display service initialized')
  }

  getState(): StatusBarState {
    return { ...this.state }
  }

  updateConfig(config: Partial<StatusBarConfig>): StatusBarState {
    try {
      // Validate partial config
      const validatedConfig = statusBarConfigSchema.partial().parse(config)
      
      // Update state
      this.state = {
        ...this.state,
        ...validatedConfig,
        lastUpdated: new Date().toISOString()
      }

      // Emit update event
      this.eventEmitter.emit('control:statusBar:update', this.state)
      
      logger.info('[StatusBar] Config updated', { mode: this.state.mode, text: this.state.text })
      
      return this.state
    } catch (error) {
      logger.error('[StatusBar] Failed to update config', error)
      throw error
    }
  }

  setMode(mode: StatusBarConfig['mode']): StatusBarState {
    return this.updateConfig({ mode })
  }

  setText(text: string | undefined): StatusBarState {
    return this.updateConfig({ text })
  }

  setVisibility(isVisible: boolean): StatusBarState {
    return this.updateConfig({ isVisible })
  }
}