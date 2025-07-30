/**
 * Type-safe interfaces for Phoenix WebSocket communication
 * Eliminates 'any' types and provides runtime validation
 */

// Core stream content interfaces
export interface StreamContentData {
  message?: string
  user?: string
  amount?: number
  tier?: string
  emote?: string
  title?: string
  category?: string
  [key: string]: unknown
}

export interface StreamContent {
  type: string
  data: StreamContentData
  priority: number
  duration?: number
  started_at: string
  id?: string
  layer?: 'foreground' | 'midground' | 'background'
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
  data: StreamContentData
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
  ticker_rotation: Array<
    | string
    | {
        type: string
        layer: 'foreground' | 'midground' | 'background'
      }
  >
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

// Base response data that most commands return
export interface BaseCommandResponseData {
  status?: 'ok' | 'error'
  error?: string
  message?: string
  [key: string]: unknown // Allow additional properties
}

// Response interfaces
export interface CommandResponse<T = BaseCommandResponseData> {
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
export interface TakeoverPayload {
  type: TakeoverCommand['type']
  message: string
  duration?: number
  timestamp: string
}

export interface TakeoverClearPayload {
  cleared_at: string
  reason?: string
}

export type StreamServiceEvent =
  | { type: 'connection_changed'; payload: ConnectionState }
  | { type: 'layer_state_updated'; payload: OverlayLayerState }
  | { type: 'queue_state_updated'; payload: StreamQueueState }
  | { type: 'show_changed'; payload: { show: string; game?: string; changed_at: string } }
  | { type: 'takeover'; payload: TakeoverPayload }
  | { type: 'takeover_clear'; payload: TakeoverClearPayload }

// Validation schemas (we'll use these for runtime validation)
export const TAKEOVER_TYPES = ['technical-difficulties', 'screen-cover', 'please-stand-by', 'custom'] as const

export const SHOW_TYPES = ['ironmon', 'variety', 'coding'] as const

export const PRIORITY_LEVELS = ['alert', 'sub_train', 'ticker'] as const

export const LAYER_PRIORITIES = ['foreground', 'midground', 'background'] as const

export const LAYER_STATES = ['hidden', 'entering', 'active', 'interrupted', 'exiting'] as const

// Type guards for runtime validation
export function isValidTakeoverType(type: string): type is TakeoverCommand['type'] {
  return TAKEOVER_TYPES.includes(type as TakeoverCommand['type'])
}

export function isValidShowType(show: string): show is OverlayLayerState['current_show'] {
  return SHOW_TYPES.includes(show as OverlayLayerState['current_show'])
}

export function isValidPriorityLevel(level: string): level is OverlayLayerState['priority_level'] {
  return PRIORITY_LEVELS.includes(level as OverlayLayerState['priority_level'])
}

// Validation functions
export function validateTakeoverCommand(cmd: unknown): cmd is TakeoverCommand {
  return (
    typeof cmd === 'object' &&
    cmd !== null &&
    isValidTakeoverType((cmd as Record<string, unknown>).type as string) &&
    typeof (cmd as Record<string, unknown>).message === 'string' &&
    ((cmd as Record<string, unknown>).duration === undefined ||
      typeof (cmd as Record<string, unknown>).duration === 'number')
  )
}

export function validateServerStreamState(state: unknown): state is ServerStreamState {
  return (
    typeof state === 'object' &&
    state !== null &&
    typeof (state as Record<string, unknown>).current_show === 'string' &&
    Array.isArray((state as Record<string, unknown>).interrupt_stack) &&
    Array.isArray((state as Record<string, unknown>).ticker_rotation) &&
    typeof (state as Record<string, unknown>).metadata === 'object' &&
    (state as Record<string, unknown>).metadata !== null &&
    typeof ((state as Record<string, unknown>).metadata as Record<string, unknown>).last_updated === 'string' &&
    typeof ((state as Record<string, unknown>).metadata as Record<string, unknown>).state_version === 'number'
  )
}

export function validateServerQueueState(state: unknown): state is ServerQueueState {
  return (
    typeof state === 'object' &&
    state !== null &&
    Array.isArray((state as Record<string, unknown>).queue) &&
    typeof (state as Record<string, unknown>).is_processing === 'boolean' &&
    typeof (state as Record<string, unknown>).metrics === 'object' &&
    (state as Record<string, unknown>).metrics !== null &&
    typeof ((state as Record<string, unknown>).metrics as Record<string, unknown>).total_items === 'number'
  )
}
