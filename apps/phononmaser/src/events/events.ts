import { EventEmitter } from 'events'
import type { EmoteAnalysis } from '@landale/shared'

export interface AudioEvents {
  'audio:started': undefined
  'audio:stopped': undefined
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
  'lm:emote_suggestion': {
    timestamp: number
    analysis: EmoteAnalysis
    suggestedEmotes: string[]
    aiEmotes: string[]
    keywordEmotes: string[]
    transcription: string
  }
}

export type AllEvents = AudioEvents & LMStudioEvents

class TypedEventEmitter extends EventEmitter {
  override emit<K extends keyof AllEvents>(
    event: K,
    ...args: AllEvents[K] extends undefined ? [] : [AllEvents[K]]
  ): boolean {
    return super.emit(event, ...args)
  }

  override on<K extends keyof AllEvents>(
    event: K,
    listener: AllEvents[K] extends undefined ? () => void : (arg: AllEvents[K]) => void
  ): this {
    return super.on(event, listener as (...args: unknown[]) => void)
  }

  override once<K extends keyof AllEvents>(
    event: K,
    listener: AllEvents[K] extends undefined ? () => void : (arg: AllEvents[K]) => void
  ): this {
    return super.once(event, listener as (...args: unknown[]) => void)
  }

  override off<K extends keyof AllEvents>(
    event: K,
    listener: AllEvents[K] extends undefined ? () => void : (arg: AllEvents[K]) => void
  ): this {
    return super.off(event, listener as (...args: unknown[]) => void)
  }
}

export const eventEmitter = new TypedEventEmitter()
