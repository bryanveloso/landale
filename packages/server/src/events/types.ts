import type { TwitchEvent } from './twitch/types'
import type { IronmonEvent } from './ironmon/types'

export type EventMap = {
  'twitch:cheer': TwitchEvent['cheer']
  'twitch:message': TwitchEvent['message']
  'ironmon:init': IronmonEvent['init']
  'ironmon:seed': IronmonEvent['seed']
  'ironmon:checkpoint': IronmonEvent['checkpoint']
  'ironmon:location': IronmonEvent['location']
}

export type SubscriptionData<T extends keyof EventMap> = {
  type: T
  data: EventMap[T]
}
