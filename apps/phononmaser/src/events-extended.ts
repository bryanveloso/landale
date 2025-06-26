import { AudioEvents, LMStudioEvents, eventEmitter } from './events'

// Extended event interface that includes both audio and LM Studio events
export interface ExtendedEvents extends AudioEvents, LMStudioEvents {}

// Helper to create typed event names
export const createEventName = <T extends keyof ExtendedEvents>(event: T): T => event

// Event categories for filtering
export const EventCategories = {
  audio: [
    'audio:started',
    'audio:stopped',
    'audio:chunk',
    'audio:buffer_ready',
    'audio:transcription'
  ] as const,
  
  lmStudio: [
    'lm:analysis_started',
    'lm:analysis_completed',
    'lm:pattern_detected',
    'lm:error'
  ] as const
} as const

// Type-safe event subscription helper
export function subscribeToCategory<K extends keyof typeof EventCategories>(
  category: K,
  callback: (event: typeof EventCategories[K][number], data: unknown) => void
) {
  const events = EventCategories[category]
  events.forEach(event => {
    eventEmitter.on(event as any, (data: unknown) => {
      callback(event, data)
    })
  })
}