import type { TwitchEvent } from './twitch/types'

export type EventMap = {
  'twitch:cheer': TwitchEvent['cheer']
  'twitch:message': TwitchEvent['message']
}

export type SubscriptionData<T extends keyof EventMap> = {
  type: T
  data: EventMap[T]
}
