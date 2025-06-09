import type { TRPCError } from '@trpc/server'
import type { EventMap } from '@/events/types'
interface SubscriptionOptions<T> {
  events: (keyof EventMap)[]
  transform?: (eventType: keyof EventMap, data: EventMap[keyof EventMap]) => T
  onError?: (error: unknown) => TRPCError
}
export declare function createEventSubscription<T>(
  opts: {
    signal?: AbortSignal
  },
  config: SubscriptionOptions<T>
): AsyncGenerator<T, void, unknown>
export declare function createPollingSubscription<T>(
  opts: {
    signal?: AbortSignal
  },
  config: {
    getData: () => T | Promise<T>
    intervalMs: number
    onError?: (error: unknown) => TRPCError
  }
): AsyncGenerator<T, void, unknown>
export {}
//# sourceMappingURL=subscription.d.ts.map
