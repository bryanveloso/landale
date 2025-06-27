import Emittery from 'emittery'
import { nanoid } from 'nanoid'
import { type EventMap } from './types'

export const eventEmitter = new Emittery<EventMap>()

export function emitEvent<T extends keyof EventMap>(event: T, data: EventMap[T]): Promise<void> {
  return eventEmitter.emit(event, data)
}

export function emitEventWithCorrelation<T extends keyof EventMap>(
  event: T,
  data: EventMap[T],
  correlationId?: string
): Promise<void> {
  const eventData = Object.assign(
    {},
    data || {},
    {
      correlationId: correlationId || nanoid(),
      timestamp: new Date().toISOString()
    }
  ) as EventMap[T]
  
  return eventEmitter.emit(event, eventData)
}

export function createEventStream<T extends keyof EventMap>(event: T) {
  return eventEmitter.events(event)
}

export function createCategoryStream(_category: string) {
  // This function needs to be rethought - eventEmitter.events is not an object
  // For now, return an empty async generator
  return (async function* () {
    // No-op for now
  })()
}

export function createSubscription<T extends keyof EventMap>(eventName: T[]) {
  return async function* () {
    const stream = eventEmitter.events(eventName)

    try {
      for await (const data of stream) {
        yield { type: eventName, data }
      }
    } finally {
      // This will be called when the client unsubscribes.
      // Additonal cleanup can be done here if needed.
    }
  }
}

export function createMultiSubscription<T extends keyof EventMap>(eventNames: T[]) {
  return async function* () {
    const streams = eventEmitter.events(eventNames)

    try {
      for await (const data of streams) {
        const eventName = eventNames.find((name) => eventEmitter.listenerCount(name) > 0) as T
        yield { type: eventName, data }
      }
    } finally {
      // This will be called when the client unsubscribes.
      // Additonal cleanup can be done here if needed.
    }
  }
}
