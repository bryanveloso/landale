/**
 * TypeScript definitions for Phoenix WebSocket events and channels
 * Replaces 'any' types with proper Phoenix event interfaces
 */

export interface PhoenixEvent {
  type: string
  data: Record<string, unknown>
  timestamp?: number
}

export interface PhoenixResponse {
  status: 'ok' | 'error' | 'timeout'
  response?: Record<string, unknown>
}

export interface PhoenixChannelState {
  channel: unknown | null
  isJoined: boolean
  topic: string
}

export interface PhoenixMessage {
  topic: string
  event: string
  payload: Record<string, unknown>
  ref?: string
}

export interface PhoenixLogger {
  (kind: string, msg: string, data: Record<string, unknown>): void
}

export interface PhoenixSocketOptions {
  logger?: PhoenixLogger
  reconnectAfterMs?: (tries: number) => number
  params?: Record<string, unknown>
}

// Stream service specific event types
export interface StreamContent {
  id: string
  type: string
  priority: number
  status?: string
  [key: string]: unknown
}

export interface StreamStateEvent extends PhoenixEvent {
  type: 'stream_state'
  data: {
    current_show: string
    active_content: StreamContent | null
    priority_level: string
    interrupt_stack: StreamContent[]
    ticker_rotation: string[]
    metadata: {
      last_updated: string
      state_version: number
    }
  }
}

export interface QueueStateEvent extends PhoenixEvent {
  type: 'queue_state'
  data: {
    queue: StreamContent[]
    active_content: StreamContent | null
    metrics: {
      total_items: number
      pending_items: number
      active_items: number
      average_wait_time: number
      last_processed: string | null
    }
    is_processing: boolean
  }
}

export interface LayerData {
  priority: 'foreground' | 'midground' | 'background'
  state: 'active' | 'hidden'
  content: StreamContent | null
}

export interface LayerStateEvent extends PhoenixEvent {
  type: 'layer_state'
  data: {
    current_show: string
    layers: {
      foreground: LayerData
      midground: LayerData
      background: LayerData
    }
    active_content: StreamContent | null
    interrupt_stack: StreamContent[]
    priority_level: string
    version: number
    last_updated: string
  }
}

export interface InitialStateEvent extends PhoenixEvent {
  type: 'initial_state'
  data: {
    connected: boolean
    timestamp: number
  }
}

export type StreamServiceEvent = StreamStateEvent | QueueStateEvent | LayerStateEvent | InitialStateEvent | PhoenixEvent

export interface EventHandler<T extends PhoenixEvent = PhoenixEvent> {
  (event: T): void
}
