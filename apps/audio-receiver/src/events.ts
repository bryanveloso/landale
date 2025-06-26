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

class TypedEventEmitter extends EventEmitter {
  emit<K extends keyof AudioEvents>(event: K, ...args: AudioEvents[K] extends void ? [] : [AudioEvents[K]]): boolean {
    return super.emit(event, ...args)
  }

  on<K extends keyof AudioEvents>(event: K, listener: (arg: AudioEvents[K]) => void): this {
    return super.on(event, listener)
  }

  once<K extends keyof AudioEvents>(event: K, listener: (arg: AudioEvents[K]) => void): this {
    return super.once(event, listener)
  }

  off<K extends keyof AudioEvents>(event: K, listener: (arg: AudioEvents[K]) => void): this {
    return super.off(event, listener)
  }
}

export const eventEmitter = new TypedEventEmitter()