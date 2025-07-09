/**
 * Type-safe interfaces for Phoenix WebSocket communication
 * Eliminates 'any' types and provides runtime validation
 */

// Core stream content interfaces
export interface StreamContent {
  type: string
  data: Record<string, any>
  priority: number
  duration?: number
  started_at: string
  id?: string
}

// Layer-specific interfaces
export interface LayerState {
  priority: 'foreground' | 'midground' | 'background'
  state: 'hidden' | 'entering' | 'active' | 'interrupted' | 'exiting'
  content: StreamContent | null
  animation_progress?: number
}

export interface OverlayLayerState {
  current_show: 'ironmon' | 'variety' | 'coding'
  layers: {
    foreground: LayerState
    midground: LayerState
    background: LayerState
  }
  active_content: StreamContent | null
  interrupt_stack: StreamContent[]
  priority_level: 'alert' | 'sub_train' | 'ticker'
  version: number
  last_updated: string
}

// Queue-specific interfaces
export interface QueueItem {
  id: string
  type: 'ticker' | 'alert' | 'sub_train' | 'manual_override'
  priority: number
  content_type: string
  data: Record<string, any>
  duration?: number
  started_at?: string
  status: 'pending' | 'active' | 'expired'
  position?: number
}

export interface QueueMetrics {
  total_items: number
  active_items: number
  pending_items: number
  average_wait_time: number
  last_processed: string | null
}

export interface StreamQueueState {
  queue: QueueItem[]
  active_content: QueueItem | null
  metrics: QueueMetrics
  is_processing: boolean
}

// Phoenix channel payload interfaces
export interface ServerStreamState {
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

export interface ServerQueueState {
  queue: QueueItem[]
  active_content: QueueItem | null
  metrics: QueueMetrics
  is_processing: boolean
}

// Command interfaces
export interface TakeoverCommand {
  type: 'technical-difficulties' | 'screen-cover' | 'please-stand-by' | 'custom'
  message: string
  duration?: number
}

export interface QueueCommand {
  type: 'clear_queue' | 'remove_queue_item' | 'reorder_queue'
  payload?: {
    id?: string
    position?: number
  }
}

// Response interfaces
export interface CommandResponse<T = any> {
  status: 'ok' | 'error'
  data?: T
  error?: string
  timestamp: string
}

export interface TakeoverResponse {
  status: 'takeover_sent' | 'takeover_cleared'
  type?: string
}

// Connection state interfaces
export interface ConnectionState {
  connected: boolean
  reconnectAttempts: number
  lastConnected: string | null
  error: string | null
}

// Service state interfaces
export interface StreamServiceState {
  connection: ConnectionState
  layerState: OverlayLayerState
  queueState: StreamQueueState
  lastUpdated: string
}

// Event types for the service
export type StreamServiceEvent =
  | { type: 'connection_changed'; payload: ConnectionState }
  | { type: 'layer_state_updated'; payload: OverlayLayerState }
  | { type: 'queue_state_updated'; payload: StreamQueueState }
  | { type: 'show_changed'; payload: { show: string; game?: string; changed_at: string } }
  | { type: 'takeover'; payload: any }
  | { type: 'takeover_clear'; payload: any }

// Validation schemas (we'll use these for runtime validation)
export const TAKEOVER_TYPES = ['technical-difficulties', 'screen-cover', 'please-stand-by', 'custom'] as const

export const SHOW_TYPES = ['ironmon', 'variety', 'coding'] as const

export const PRIORITY_LEVELS = ['alert', 'sub_train', 'ticker'] as const

export const LAYER_PRIORITIES = ['foreground', 'midground', 'background'] as const

export const LAYER_STATES = ['hidden', 'entering', 'active', 'interrupted', 'exiting'] as const

// Type guards for runtime validation
export function isValidTakeoverType(type: string): type is TakeoverCommand['type'] {
  return TAKEOVER_TYPES.includes(type as any)
}

export function isValidShowType(show: string): show is OverlayLayerState['current_show'] {
  return SHOW_TYPES.includes(show as any)
}

export function isValidPriorityLevel(level: string): level is OverlayLayerState['priority_level'] {
  return PRIORITY_LEVELS.includes(level as any)
}

// Validation functions
export function validateTakeoverCommand(cmd: any): cmd is TakeoverCommand {
  return (
    typeof cmd === 'object' &&
    cmd !== null &&
    isValidTakeoverType(cmd.type) &&
    typeof cmd.message === 'string' &&
    (cmd.duration === undefined || typeof cmd.duration === 'number')
  )
}

export function validateServerStreamState(state: any): state is ServerStreamState {
  return (
    typeof state === 'object' &&
    state !== null &&
    typeof state.current_show === 'string' &&
    Array.isArray(state.interrupt_stack) &&
    Array.isArray(state.ticker_rotation) &&
    state.metadata &&
    typeof state.metadata.last_updated === 'string' &&
    typeof state.metadata.state_version === 'number'
  )
}

export function validateServerQueueState(state: any): state is ServerQueueState {
  return (
    typeof state === 'object' &&
    state !== null &&
    Array.isArray(state.queue) &&
    typeof state.is_processing === 'boolean' &&
    state.metrics &&
    typeof state.metrics.total_items === 'number'
  )
}
