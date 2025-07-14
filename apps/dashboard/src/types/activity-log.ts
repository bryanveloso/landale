/**
 * Type definitions for Activity Log functionality
 * Matches backend ActivityLog Event and User schemas
 */

// Event data structures for different event types
export interface ChatMessageData {
  message: string
  fragments?: Array<{
    type: 'text' | 'emote'
    text: string
    cheermote?: unknown
    emote?: unknown
  }>
  color?: string
  badges?: Array<{
    set_id: string
    id: string
    info: string
  }>
}

export interface FollowData {
  followed_at: string
}

export interface SubscriptionData {
  tier: string
  is_gift: boolean
  cumulative_months?: number
  streak_months?: number
  duration_months?: number
  message?: {
    text: string
    emotes?: unknown[]
  }
}

export interface CheerData {
  bits: number
  message: string
}

export interface ChannelUpdateData {
  title?: string
  category_name?: string
  category_id?: string
  language?: string
}

export interface StreamStatusData {
  type: string
  started_at?: string
}

export type ActivityEventData = 
  | ChatMessageData
  | FollowData  
  | SubscriptionData
  | CheerData
  | ChannelUpdateData
  | StreamStatusData
  | Record<string, unknown>

// Core activity event interface (matches backend Event schema)
export interface ActivityEvent {
  id: string
  timestamp: string
  event_type: string
  user_id: string | null
  user_login: string | null
  user_name: string | null
  data: ActivityEventData
  correlation_id: string | null
}

// Activity user interface (matches backend User schema)
export interface ActivityUser {
  twitch_id: string
  login: string
  display_name: string | null
  nickname: string | null
  pronouns: string | null
  notes: string | null
}

// Filter options for activity log
export interface ActivityLogFilters {
  event_type?: string
  user_id?: string
  limit?: number
}

// Activity log state management
export interface ActivityLogState {
  events: ActivityEvent[]
  loading: boolean
  error: string | null
  hasMore: boolean
  filters: ActivityLogFilters
}

// API response interfaces
export interface ActivityEventsResponse {
  success: boolean
  data: {
    events: ActivityEvent[]
    count: number
  }
  meta: {
    timestamp: string
    server_version: string
  }
}

export interface ActivityStatsResponse {
  success: boolean
  data: {
    stats: {
      total_events: number
      unique_users: number
      chat_messages: number
      follows: number
      subscriptions: number
      cheers: number
    }
    most_active_users: Array<{
      user_login: string
      message_count: number
    }>
    time_window_hours: number
  }
}

// Event type constants for filtering
export const EVENT_TYPES = {
  CHAT_MESSAGE: 'channel.chat.message',
  CHAT_CLEAR: 'channel.chat.clear',
  MESSAGE_DELETE: 'channel.chat.message_delete',
  FOLLOW: 'channel.follow',
  SUBSCRIBE: 'channel.subscribe',
  GIFT_SUB: 'channel.subscription.gift',
  CHEER: 'channel.cheer',
  CHANNEL_UPDATE: 'channel.update',
  STREAM_ONLINE: 'stream.online',
  STREAM_OFFLINE: 'stream.offline'
} as const

export type EventType = typeof EVENT_TYPES[keyof typeof EVENT_TYPES]

// Event type display names for UI
export const EVENT_TYPE_LABELS: Record<EventType, string> = {
  [EVENT_TYPES.CHAT_MESSAGE]: 'Chat',
  [EVENT_TYPES.CHAT_CLEAR]: 'Chat Clear',
  [EVENT_TYPES.MESSAGE_DELETE]: 'Message Delete',
  [EVENT_TYPES.FOLLOW]: 'Follow',
  [EVENT_TYPES.SUBSCRIBE]: 'Subscribe',
  [EVENT_TYPES.GIFT_SUB]: 'Gift Sub',
  [EVENT_TYPES.CHEER]: 'Cheer',
  [EVENT_TYPES.CHANNEL_UPDATE]: 'Channel Update',
  [EVENT_TYPES.STREAM_ONLINE]: 'Stream Online',
  [EVENT_TYPES.STREAM_OFFLINE]: 'Stream Offline'
}

// Type guards for runtime validation
export function isValidEventType(type: string): type is EventType {
  return Object.values(EVENT_TYPES).includes(type as EventType)
}

export function isActivityEvent(obj: unknown): obj is ActivityEvent {
  return (
    typeof obj === 'object' &&
    obj !== null &&
    typeof (obj as Record<string, unknown>).id === 'string' &&
    typeof (obj as Record<string, unknown>).timestamp === 'string' &&
    typeof (obj as Record<string, unknown>).event_type === 'string' &&
    typeof (obj as Record<string, unknown>).data === 'object'
  )
}