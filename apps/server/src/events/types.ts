import type { TwitchEvent } from '@/services/twitch/types'
import type { IronmonEvent } from '@/services/ironmon/types'
import type { StatusBarState, StatusTextState } from '@/types/control'
import type { RainwaveNowPlaying } from '@landale/shared'

// Control API event types
export type ControlEvent = {
  sourceConnected: { id: string; type: string }
  sourceDisconnected: { id: string }
  sourcePing: { id: string }
  overlayConfigUpdated: { overlayId: string; config: Record<string, unknown> }
  emoteRainBurst: { emoteId?: string; count: number }
  emoteRainClear: void
  sourceReload: string
  statusBarUpdate: StatusBarState
  statusTextUpdate: StatusTextState
}

// OBS event types - these match the events emitted by the OBS service
export type OBSEvent = {
  connectionChanged: any
  scenesUpdated: any
  sceneCurrentChanged: any
  scenePreviewChanged: any
  sceneListChanged: any
  streamingUpdated: any
  streamStateChanged: any
  recordingUpdated: any
  recordStateChanged: any
  studioModeUpdated: any
  studioModeChanged: any
  virtualCamUpdated: any
  virtualCamChanged: any
  replayBufferUpdated: any
  replayBufferChanged: any
}

export type EventMap = {
  'twitch:cheer': TwitchEvent['cheer']
  'twitch:message': TwitchEvent['message']
  'twitch:follow': TwitchEvent['follow']
  'twitch:subscription': TwitchEvent['subscription']
  'twitch:subscription:gift': TwitchEvent['subscriptionGift']
  'twitch:subscription:message': TwitchEvent['subscriptionMessage']
  'twitch:redemption': TwitchEvent['redemption']
  'twitch:stream:online': TwitchEvent['streamOnline']
  'twitch:stream:offline': TwitchEvent['streamOffline']
  'ironmon:init': IronmonEvent['init']
  'ironmon:seed': IronmonEvent['seed']
  'ironmon:checkpoint': IronmonEvent['checkpoint']
  'ironmon:location': IronmonEvent['location']
  'control:source:connected': ControlEvent['sourceConnected']
  'control:source:disconnected': ControlEvent['sourceDisconnected']
  'control:source:ping': ControlEvent['sourcePing']
  'control:statusBar:update': ControlEvent['statusBarUpdate']
  'control:statusText:update': ControlEvent['statusTextUpdate']
  'config:emoteRain:updated': Record<string, unknown>
  'emoteRain:burst': ControlEvent['emoteRainBurst']
  'emoteRain:clear': ControlEvent['emoteRainClear']
  'source:reload': ControlEvent['sourceReload']
  'obs:connection:changed': OBSEvent['connectionChanged']
  'obs:scenes:updated': OBSEvent['scenesUpdated']
  'obs:scene:current-changed': OBSEvent['sceneCurrentChanged']
  'obs:scene:preview-changed': OBSEvent['scenePreviewChanged']
  'obs:scene:list-changed': OBSEvent['sceneListChanged']
  'obs:streaming:updated': OBSEvent['streamingUpdated']
  'obs:stream:state-changed': OBSEvent['streamStateChanged']
  'obs:recording:updated': OBSEvent['recordingUpdated']
  'obs:record:state-changed': OBSEvent['recordStateChanged']
  'obs:studio-mode:updated': OBSEvent['studioModeUpdated']
  'obs:studio-mode:changed': OBSEvent['studioModeChanged']
  'obs:virtual-cam:updated': OBSEvent['virtualCamUpdated']
  'obs:virtual-cam:changed': OBSEvent['virtualCamChanged']
  'obs:replay-buffer:updated': OBSEvent['replayBufferUpdated']
  'obs:replay-buffer:changed': OBSEvent['replayBufferChanged']
  'rainwave:update': RainwaveNowPlaying
  // Generic display events - any string after 'display:' is allowed
  [key: `display:${string}:update`]: any
}

export type SubscriptionData<T extends keyof EventMap> = {
  type: T
  data: EventMap[T]
}
