import type Emittery from 'emittery'
import type { EventMap } from '@/events/types'
import type { StatusTextConfig, StatusTextState } from '@/types/control'
import { statusTextConfigSchema } from '@/types/control'
import { logger } from '@/lib/logger'

export class StatusTextService {
  private state: StatusTextState
  private readonly eventEmitter: Emittery<EventMap>

  constructor(eventEmitter: Emittery<EventMap>) {
    this.eventEmitter = eventEmitter
    
    // Initialize with default state
    this.state = {
      text: '',
      isVisible: true,
      position: 'bottom',
      fontSize: 'medium',
      animation: 'fade',
      lastUpdated: new Date().toISOString()
    }

    logger.info('[StatusText] Display service initialized')
  }

  getState(): StatusTextState {
    return { ...this.state }
  }

  updateConfig(config: Partial<StatusTextConfig>): StatusTextState {
    try {
      // Validate partial config
      const validatedConfig = statusTextConfigSchema.partial().parse(config)
      
      // Update state
      this.state = {
        ...this.state,
        ...validatedConfig,
        lastUpdated: new Date().toISOString()
      }

      // Emit update event
      this.eventEmitter.emit('control:statusText:update', this.state)
      
      logger.info('[StatusText] Config updated', { text: this.state.text })
      
      return this.state
    } catch (error) {
      logger.error('[StatusText] Failed to update config', error)
      throw error
    }
  }

  setText(text: string): StatusTextState {
    return this.updateConfig({ text })
  }

  setVisibility(isVisible: boolean): StatusTextState {
    return this.updateConfig({ isVisible })
  }

  clear(): StatusTextState {
    return this.updateConfig({ text: '', isVisible: false })
  }
}