import { createSignal, createEffect, onCleanup } from 'solid-js'
import { Channel } from 'phoenix'
import { usePhoenixService } from '@/services/phoenix-service'
import type { ActivityEvent, ActivityLogFilters } from '@/types/activity-log'

export function useActivityLog() {
  const { socket, isConnected } = usePhoenixService()
  const [events, setEvents] = createSignal<ActivityEvent[]>([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal<string | null>(null)
  const [hasMore] = createSignal(false)
  const [filters, setFilters] = createSignal<ActivityLogFilters>({ limit: 50 })
  const [eventsChannel, setEventsChannel] = createSignal<Channel | null>(null)

  const addEvent = (event: ActivityEvent) => {
    setEvents((prev) => [event, ...prev].slice(0, 1000))
  }

  // Transform flat Twitch events to ActivityEvent format
  const transformTwitchEvent = (event: Record<string, unknown>): ActivityEvent | null => {
    if (!event || !event.type) return null

    return {
      id: (event.id as string) || crypto.randomUUID(),
      timestamp: (event.timestamp as string) || new Date().toISOString(),
      event_type: event.type as string,
      user_id: (event.user_id as string) || null,
      user_login: (event.user_login as string) || null,
      user_name: (event.user_name as string) || null,
      data: event, // Store the full flat event as data
      correlation_id: (event.correlation_id as string) || null
    }
  }

  // Load initial events from API
  const loadInitialEvents = async () => {
    setLoading(true)
    setError(null)

    try {
      const response = await fetch('http://saya:7175/api/activity/events?limit=50')
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const data = await response.json()
      if (data.success && data.data?.events) {
        setEvents(data.data.events)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load events')
    } finally {
      setLoading(false)
    }
  }

  createEffect(() => {
    const connected = isConnected()
    const phoenixSocket = socket()

    if (connected && phoenixSocket && !eventsChannel()) {
      // Connect to dashboard channel to receive Twitch events
      const channel = phoenixSocket.channel('dashboard:main', {})

      // Listen for flat Twitch events
      channel.on('twitch_event', (event: Record<string, unknown>) => {
        const activityEvent = transformTwitchEvent(event)
        if (activityEvent) addEvent(activityEvent)
      })

      channel
        .join()
        .receive('ok', () => {
          // Load initial events after successful channel join
          loadInitialEvents()
        })
        .receive('error', (_reason: unknown) => {
          setError('Failed to connect to real-time updates')
        })

      setEventsChannel(channel)
    } else if (!connected && eventsChannel()) {
      eventsChannel()?.leave()
      setEventsChannel(null)
    }
  })

  onCleanup(() => {
    eventsChannel()?.leave()
  })

  return {
    events,
    loading,
    error,
    hasMore,
    filters,
    applyFilters: (newFilters: Partial<ActivityLogFilters>) => setFilters((prev) => ({ ...prev, ...newFilters })),
    clearFilters: () => setFilters({ limit: 50 }),
    loadMore: () => {},
    refetch: loadInitialEvents
  }
}
