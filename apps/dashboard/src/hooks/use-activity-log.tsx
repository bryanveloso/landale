/**
 * Activity Log hook for consuming activity events and managing state
 *
 * Provides API integration for historical events and will eventually
 * integrate with real-time events via StreamService
 */

import { createSignal, createEffect, createMemo, onCleanup } from 'solid-js'
import { Channel } from 'phoenix'
import { createLogger } from '@landale/logger/browser'
import { useSocket } from '@/providers/socket-provider'
import type { 
  ActivityEvent, 
  ActivityLogState, 
  ActivityLogFilters,
  ActivityEventsResponse,
  ActivityStatsResponse 
} from '@/types/activity-log'
import { EVENT_TYPES } from '@/types/activity-log'

const logger = createLogger({
  service: 'dashboard-activity-log',
  level: 'info',
  enableConsole: true
})

const DEFAULT_ACTIVITY_STATE: ActivityLogState = {
  events: [],
  loading: false,
  error: null,
  hasMore: true,
  filters: {
    limit: 50
  }
}

export function useActivityLog() {
  const { socket, isConnected } = useSocket()
  const [state, setState] = createSignal<ActivityLogState>(DEFAULT_ACTIVITY_STATE)
  const [eventsChannel, setEventsChannel] = createSignal<Channel | null>(null)

  // Fetch historical events from API
  const fetchEvents = async (filters?: ActivityLogFilters) => {
    setState(prev => ({ ...prev, loading: true, error: null }))

    try {
      const params = new URLSearchParams()
      
      if (filters?.limit) {
        params.append('limit', filters.limit.toString())
      }
      if (filters?.event_type) {
        params.append('event_type', filters.event_type)
      }
      if (filters?.user_id) {
        params.append('user_id', filters.user_id)
      }

      const response = await fetch(`/api/activity/events?${params}`)
      
      if (!response.ok) {
        throw new Error(`Failed to fetch events: ${response.status}`)
      }

      const data: ActivityEventsResponse = await response.json()

      if (!data.success) {
        throw new Error('API returned error response')
      }

      setState(prev => ({
        ...prev,
        events: data.data.events,
        loading: false,
        hasMore: data.data.events.length === (filters?.limit || 50),
        filters: filters || prev.filters
      }))

    } catch (error) {
      logger.error('Failed to fetch activity events', {
        error: {
          message: error instanceof Error ? error.message : String(error),
          type: error instanceof Error ? error.constructor.name : typeof error,
          stack: error instanceof Error ? error.stack : undefined
        },
        context: {
          filters,
          operation: 'fetch_events'
        }
      })
      setState(prev => ({
        ...prev,
        loading: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }))
    }
  }

  // Fetch activity statistics
  const fetchStats = async (hours: number = 24) => {
    try {
      const response = await fetch(`/api/activity/stats?hours=${hours}`)
      
      if (!response.ok) {
        throw new Error(`Failed to fetch stats: ${response.status}`)
      }

      const data: ActivityStatsResponse = await response.json()

      if (!data.success) {
        throw new Error('API returned error response')
      }

      return data.data

    } catch (error) {
      logger.error('Failed to fetch activity stats', {
        error: {
          message: error instanceof Error ? error.message : String(error),
          type: error instanceof Error ? error.constructor.name : typeof error,
          stack: error instanceof Error ? error.stack : undefined
        },
        context: {
          hours,
          operation: 'fetch_stats'
        }
      })
      throw error
    }
  }

  // Apply filters to events
  const applyFilters = (filters: ActivityLogFilters) => {
    fetchEvents(filters)
  }

  // Clear all filters
  const clearFilters = () => {
    const defaultFilters = { limit: 50 }
    fetchEvents(defaultFilters)
  }

  // Load more events (pagination)
  const loadMore = () => {
    const currentState = state()
    if (currentState.loading || !currentState.hasMore) return

    // For now, just increase the limit
    // In future, this could use offset-based pagination
    const newLimit = (currentState.filters.limit || 50) + 50
    applyFilters({
      ...currentState.filters,
      limit: newLimit
    })
  }

  // Add a new event in real-time from EventsChannel
  const addEvent = (event: ActivityEvent) => {
    setState(prev => {
      // Check for duplicates by ID to prevent double-adding
      const existingIds = new Set(prev.events.map(e => e.id))
      if (existingIds.has(event.id)) {
        return prev
      }

      // Add to front of list for chronological order
      return {
        ...prev,
        events: [event, ...prev.events]
      }
    })
  }

  // Create memoized accessors
  const memoizedEvents = createMemo(() => state().events)
  const memoizedLoading = createMemo(() => state().loading)
  const memoizedError = createMemo(() => state().error)
  const memoizedHasMore = createMemo(() => state().hasMore)
  const memoizedFilters = createMemo(() => state().filters)

  // Transform EventsChannel messages to ActivityEvent format
  const transformEventMessage = (eventType: string, payload: any): ActivityEvent | null => {
    try {
      switch (eventType) {
        case 'chat_message':
          return {
            id: payload.data?.id || crypto.randomUUID(),
            timestamp: payload.timestamp || new Date().toISOString(),
            event_type: EVENT_TYPES.CHAT_MESSAGE,
            user_id: payload.data?.user_id || null,
            user_login: payload.data?.user_login || null,
            user_name: payload.data?.user_name || null,
            data: {
              message: payload.data?.message || '',
              badges: payload.data?.badges || [],
              emotes: payload.data?.emotes || []
            },
            correlation_id: payload.data?.correlation_id || null
          }

        case 'follower':
          return {
            id: payload.data?.id || crypto.randomUUID(),
            timestamp: payload.timestamp || new Date().toISOString(),
            event_type: EVENT_TYPES.FOLLOW,
            user_id: payload.data?.user_id || null,
            user_login: payload.data?.user_login || null,
            user_name: payload.data?.user_name || null,
            data: payload.data || {},
            correlation_id: null
          }

        case 'subscription':
          return {
            id: payload.data?.id || crypto.randomUUID(),
            timestamp: payload.timestamp || new Date().toISOString(),
            event_type: EVENT_TYPES.SUBSCRIBE,
            user_id: payload.data?.user_id || null,
            user_login: payload.data?.user_login || null,
            user_name: payload.data?.user_name || null,
            data: {
              tier: payload.data?.tier || 1,
              months: payload.data?.months || 1,
              message: payload.data?.message || null
            },
            correlation_id: null
          }

        case 'cheer':
          return {
            id: payload.data?.id || crypto.randomUUID(),
            timestamp: payload.timestamp || new Date().toISOString(),
            event_type: EVENT_TYPES.CHEER,
            user_id: payload.data?.user_id || null,
            user_login: payload.data?.user_login || null,
            user_name: payload.data?.user_name || null,
            data: {
              bits: payload.data?.bits || 0,
              message: payload.data?.message || null
            },
            correlation_id: null
          }

        default:
          logger.warn('Unknown event type received from EventsChannel', {
            eventType,
            payload
          })
          return null
      }
    } catch (error) {
      logger.error('Failed to transform event message', {
        error: {
          message: error instanceof Error ? error.message : String(error),
          type: error instanceof Error ? error.constructor.name : typeof error
        },
        context: { eventType, payload }
      })
      return null
    }
  }

  // Setup EventsChannel connection for real-time events
  const setupEventsChannel = () => {
    const currentSocket = socket()
    if (!currentSocket || !isConnected() || eventsChannel()) return

    logger.info('Setting up EventsChannel for real-time activity events')

    const channel = currentSocket.channel('events:all', {})

    // Handle different event types
    channel.on('chat_message', (payload) => {
      const event = transformEventMessage('chat_message', payload)
      if (event) addEvent(event)
    })

    channel.on('follower', (payload) => {
      const event = transformEventMessage('follower', payload)
      if (event) addEvent(event)
    })

    channel.on('subscription', (payload) => {
      const event = transformEventMessage('subscription', payload)
      if (event) addEvent(event)
    })

    channel.on('gift_subscription', (payload) => {
      const event = transformEventMessage('subscription', payload)
      if (event) addEvent(event)
    })

    channel.on('cheer', (payload) => {
      const event = transformEventMessage('cheer', payload)
      if (event) addEvent(event)
    })

    // Join channel
    channel
      .join()
      .receive('ok', () => {
        logger.info('Successfully joined EventsChannel for activity events')
        setEventsChannel(channel)
      })
      .receive('error', (resp) => {
        logger.error('Failed to join EventsChannel', {
          error: { message: resp?.error?.message || resp?.reason || 'unknown' },
          context: { operation: 'join_events_channel' }
        })
      })
      .receive('timeout', () => {
        logger.error('EventsChannel join timeout', {
          context: { operation: 'join_events_channel' }
        })
      })
  }

  // Cleanup EventsChannel connection
  const cleanupEventsChannel = () => {
    const channel = eventsChannel()
    if (channel) {
      logger.info('Cleaning up EventsChannel connection')
      channel.leave()
      setEventsChannel(null)
    }
  }

  // Setup channel when socket connects
  createEffect(() => {
    if (isConnected()) {
      setupEventsChannel()
    } else {
      cleanupEventsChannel()
    }
  })

  // Initialize with data fetch
  createEffect(() => {
    fetchEvents()
  })

  // Cleanup on unmount
  onCleanup(() => {
    cleanupEventsChannel()
  })

  return {
    // State (memoized for better reactivity)
    state,
    events: memoizedEvents,
    loading: memoizedLoading,
    error: memoizedError,
    hasMore: memoizedHasMore,
    filters: memoizedFilters,

    // Actions
    fetchEvents,
    fetchStats,
    applyFilters,
    clearFilters,
    loadMore,
    addEvent,

    // Utility
    refresh: () => fetchEvents(state().filters)
  }
}