import type { TRPCError } from '@trpc/server'
import { eventEmitter } from '@/events'
import type { EventMap } from '@/events/types'

interface SubscriptionOptions<T> {
  events: (keyof EventMap)[]
  transform?: (eventType: keyof EventMap, data: EventMap[keyof EventMap]) => T
  onError?: (error: unknown) => TRPCError
}

export async function* createEventSubscription<T>(
  opts: { signal?: AbortSignal },
  config: SubscriptionOptions<T>
): AsyncGenerator<T, void, unknown> {
  const unsubscribers: (() => void)[] = []
  const queue: T[] = []
  let resolveNext: ((value: IteratorResult<T>) => void) | null = null

  try {
    // Subscribe to events
    for (const eventType of config.events) {
      // Create a properly typed handler for this specific event type
      const handleEvent = (data: EventMap[keyof EventMap]) => {
        const transformedData = config.transform ? config.transform(eventType, data) : (data as T)

        if (resolveNext) {
          resolveNext({ value: transformedData, done: false })
          resolveNext = null
        } else {
          queue.push(transformedData)
        }
      }

      // Use type assertion for the event handler since we know it's safe
      const unsubscribe = eventEmitter.on(eventType, handleEvent as Parameters<typeof eventEmitter.on>[1])
      unsubscribers.push(unsubscribe)
    }

    // Process events
    while (!opts.signal?.aborted) {
      if (queue.length > 0) {
        yield queue.shift() as T
      } else {
        yield await new Promise<T>((resolve) => {
          resolveNext = (result: IteratorResult<T>) => {
            resolve(result.value as T)
          }
        })
      }
    }
  } catch (error) {
    if (config.onError) {
      throw config.onError(error)
    }
    throw error
  } finally {
    unsubscribers.forEach((fn) => {
      fn()
    })
  }
}

export async function* createPollingSubscription<T>(
  opts: { signal?: AbortSignal },
  config: {
    getData: () => T | Promise<T>
    intervalMs: number
    onError?: (error: unknown) => TRPCError
  }
): AsyncGenerator<T, void, unknown> {
  try {
    while (!opts.signal?.aborted) {
      const data = await config.getData()
      yield data

      await new Promise((resolve) => setTimeout(resolve, config.intervalMs))
    }
  } catch (error) {
    if (config.onError) {
      throw config.onError(error)
    }
    throw error
  }
}
