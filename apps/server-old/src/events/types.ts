import type { TwitchEvent } from '@/services/twitch/types'
import type { IronmonEvent } from '@/services/ironmon/types'
import type { StatusBarState, StatusTextState } from '@/types/control'
import type { RainwaveNowPlaying } from '@landale/shared'
import type { PerformanceMetric, StreamHealthMetric } from '@/lib/performance'
import type { AuditEvent } from '@/lib/audit'

// Control API event types
export type ControlEvent = {
  sourceConnected: { id: string; type: string }
  sourceDisconnected: { id: string }
  sourcePing: { id: string }
  overlayConfigUpdated: { overlayId: string; config: Record<string, unknown> }
  emoteRainBurst: { emoteId?: string; count: number }
  emoteRainClear: undefined
  sourceReload: string
  statusBarUpdate: StatusBarState
  statusTextUpdate: StatusTextState
}

// OBS event types - these match the events emitted by the OBS service
export type OBSEvent = {
  connectionChanged: {
    connected: boolean
    connectionState: 'disconnected' | 'connecting' | 'connected' | 'error'
    lastError?: string
    lastConnected?: Date
    obsStudioVersion?: string
    obsWebSocketVersion?: string
    negotiatedRpcVersion?: number
  }
  scenesUpdated: {
    current: string | null
    preview: string | null
    list: Array<{ sceneName?: string; sceneIndex?: number; sceneUuid?: string; [key: string]: unknown }>
  }
  sceneCurrentChanged: { sceneName: string; sceneUuid?: string }
  scenePreviewChanged: { sceneName: string; sceneUuid?: string }
  sceneListChanged: { scenes: Array<{ sceneName?: string; sceneIndex?: number; sceneUuid?: string }> }
  streamingUpdated: {
    active: boolean
    reconnecting: boolean
    timecode: string
    duration: number
    congestion: number
    bytes: number
    skippedFrames: number
    totalFrames: number
  }
  streamStateChanged: { outputActive: boolean; outputState: string }
  recordingUpdated: {
    active: boolean
    paused: boolean
    timecode: string
    duration: number
    bytes: number
    outputPath?: string
  }
  recordStateChanged: { outputActive: boolean; outputState: string; outputPaused?: boolean }
  studioModeUpdated: { enabled: boolean }
  studioModeChanged: { studioModeEnabled: boolean }
  virtualCamUpdated: { active: boolean }
  virtualCamChanged: { outputActive: boolean; outputState: string }
  replayBufferUpdated: { active: boolean }
  replayBufferChanged: { outputActive: boolean; outputState: string }
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
  // Performance and audit events
  'performance:metric': PerformanceMetric
  'performance:critical': {
    operation: string
    category: string
    duration: number
    threshold: number
    metadata?: Record<string, unknown>
  }
  'streamHealth:metric': StreamHealthMetric
  'streamHealth:alert': {
    alerts: string[]
    health: StreamHealthMetric
    timestamp: Date
  }
  'audit:event': AuditEvent
  // Health monitoring events
  'health:status': {
    status: 'healthy' | 'degraded' | 'unhealthy' | 'unknown'
    services: Array<{
      name: string
      status: 'healthy' | 'degraded' | 'unhealthy' | 'unknown'
      lastCheck: Date
      lastSuccessfulCheck?: Date
      error?: string
      metadata?: Record<string, unknown>
    }>
    timestamp: string
  }
  'health:alert': {
    service: string
    status: 'healthy' | 'degraded' | 'unhealthy' | 'unknown'
    error?: string
    timestamp: string
  }
  // Generic display events - any string after 'display:' is allowed
  [key: `display:${string}:update`]: unknown
}

export type SubscriptionData<T extends keyof EventMap> = {
  type: T
  data: EventMap[T]
}
