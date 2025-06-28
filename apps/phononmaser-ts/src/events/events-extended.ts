import type { AudioEvents } from './events'
import { eventEmitter } from './events'

// Type alias for audio events
export type ExtendedEvents = AudioEvents

// Helper to create typed event names
export const createEventName = <T extends keyof ExtendedEvents>(event: T): T => event

// Event categories for filtering
export const EventCategories = {
  audio: ['audio:started', 'audio:stopped', 'audio:chunk', 'audio:buffer_ready', 'audio:transcription'] as const,

} as const

// Type-safe event subscription helper
export function subscribeToCategory<K extends keyof typeof EventCategories>(
  category: K,
  callback: (event: (typeof EventCategories)[K][number], data: unknown) => void
) {
  const events = EventCategories[category]
  events.forEach((event) => {
    eventEmitter.on(event as keyof ExtendedEvents, (data: ExtendedEvents[keyof ExtendedEvents]) => {
      callback(event, data)
    })
  })
}
