/**
 * Activity Log hook for consuming activity events and managing state
 *
 * Provides API integration for historical events and will eventually
 * integrate with real-time events via StreamService
 */

import { createSignal, createEffect, createMemo } from 'solid-js'
import { createLogger } from '@landale/logger/browser'
import type { 
  ActivityEvent, 
  ActivityLogState, 
  ActivityLogFilters,
  ActivityEventsResponse,
  ActivityStatsResponse 
} from '@/types/activity-log'

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
  const [state, setState] = createSignal<ActivityLogState>(DEFAULT_ACTIVITY_STATE)

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

  // Add a new event in real-time (for future WebSocket integration)
  const addEvent = (event: ActivityEvent) => {
    setState(prev => ({
      ...prev,
      events: [event, ...prev.events]
    }))
  }

  // Create memoized accessors
  const memoizedEvents = createMemo(() => state().events)
  const memoizedLoading = createMemo(() => state().loading)
  const memoizedError = createMemo(() => state().error)
  const memoizedHasMore = createMemo(() => state().hasMore)
  const memoizedFilters = createMemo(() => state().filters)

  // Initialize with data fetch
  createEffect(() => {
    fetchEvents()
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