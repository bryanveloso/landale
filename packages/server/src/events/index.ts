import Emittery from 'emittery'
import { type EventMap } from './types'

export const eventEmitter = new Emittery<EventMap>()

export function emitEvent<T extends keyof EventMap>(event: T, data: EventMap[T]): Promise<void> {
  return eventEmitter.emit(event, data)
}

export function createEventStream<T extends keyof EventMap>(event: T) {
  return eventEmitter.events(event)
}

export function createCategoryStream<T extends string>(category: T) {
  // Filter event names that start with the category.
  const eventNames = Object.keys(eventEmitter.events).filter((event) =>
    event.startsWith(`${category}:`)
  ) as (keyof EventMap)[]
  return eventEmitter.events(eventNames)
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
