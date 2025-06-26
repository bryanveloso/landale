import { EventEmitter } from 'events'

export interface AudioEvents {
  'audio:started': void
  'audio:stopped': void
  'audio:chunk': {
    timestamp: number
    sourceId: string
    sourceName: string
    size: number
  }
  'audio:buffer_ready': {
    startTimestamp: number
    endTimestamp: number
    duration: number
    format: {
      sampleRate: number
      channels: number
      bitDepth: number
    }
    pcmData: Buffer
    size: number
  }
  'audio:transcription': {
    timestamp: number
    duration: number
    text: string
    confidence?: number
  }
}

export interface LMStudioEvents {
  'lm:analysis_started': {
    contextSize: number
    immediate: boolean
  }
  'lm:analysis_completed': {
    timestamp: number
    analysis: {
      patterns: {
        technical_discussion: number
        excitement: number
        frustration: number
        game_event: number
        viewer_interaction: number
        question: number
      }
      suggestedActions: string[]
      sentiment: 'positive' | 'negative' | 'neutral'
      topics: string[]
      context: string
    }
    contextSize: number
  }
  'lm:pattern_detected': {
    pattern: string
    confidence: number
    context: string
    suggestedActions: string[]
  }
  'lm:error': {
    error: string
    timestamp: number
  }
}

export type AllEvents = AudioEvents & LMStudioEvents

class TypedEventEmitter extends EventEmitter {
  emit<K extends keyof AllEvents>(event: K, ...args: AllEvents[K] extends void ? [] : [AllEvents[K]]): boolean {
    return super.emit(event, ...args)
  }

  on<K extends keyof AllEvents>(event: K, listener: (arg: AllEvents[K]) => void): this {
    return super.on(event, listener)
  }

  once<K extends keyof AllEvents>(event: K, listener: (arg: AllEvents[K]) => void): this {
    return super.once(event, listener)
  }

  off<K extends keyof AllEvents>(event: K, listener: (arg: AllEvents[K]) => void): this {
    return super.off(event, listener)
  }
}

export const eventEmitter = new TypedEventEmitter()