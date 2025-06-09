import Emittery from 'emittery'
import { type EventMap } from './types'
export declare const eventEmitter: Emittery<EventMap, any, any>
export declare function emitEvent<T extends keyof EventMap>(event: T, data: EventMap[T]): Promise<void>
export declare function createEventStream<T extends keyof EventMap>(event: T): AsyncIterableIterator<EventMap>
export declare function createCategoryStream<T extends string>(category: T): AsyncIterableIterator<EventMap>
export declare function createSubscription<T extends keyof EventMap>(
  eventName: T[]
): () => AsyncGenerator<
  {
    type: T[]
    data: EventMap
  },
  void,
  unknown
>
export declare function createMultiSubscription<T extends keyof EventMap>(
  eventNames: T[]
): () => AsyncGenerator<
  {
    type: T
    data: EventMap
  },
  void,
  unknown
>
//# sourceMappingURL=index.d.ts.map
