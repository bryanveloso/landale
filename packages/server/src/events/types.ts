import type { TwitchEvent } from './twitch/types'
import type { IronmonEvent } from './ironmon/types'

// Control API event types
export type ControlEvent = {
  sourceConnected: { id: string; type: string }
  sourceDisconnected: { id: string }
  sourcePing: { id: string }
  overlayConfigUpdated: { overlayId: string; config: Record<string, unknown> }
  emoteRainBurst: { emoteId?: string; count: number }
  emoteRainClear: void
  sourceReload: string
}

export type EventMap = {
  'twitch:cheer': TwitchEvent['cheer']
  'twitch:message': TwitchEvent['message']
  'ironmon:init': IronmonEvent['init']
  'ironmon:seed': IronmonEvent['seed']
  'ironmon:checkpoint': IronmonEvent['checkpoint']
  'ironmon:location': IronmonEvent['location']
  'control:source:connected': ControlEvent['sourceConnected']
  'control:source:disconnected': ControlEvent['sourceDisconnected']
  'control:source:ping': ControlEvent['sourcePing']
  'config:emoteRain:updated': Record<string, unknown>
  'emoteRain:burst': ControlEvent['emoteRainBurst']
  'emoteRain:clear': ControlEvent['emoteRainClear']
  'source:reload': ControlEvent['sourceReload']
}

export type SubscriptionData<T extends keyof EventMap> = {
  type: T
  data: EventMap[T]
}
