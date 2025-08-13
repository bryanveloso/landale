import { createSignal, createEffect, onCleanup } from 'solid-js'
import { Channel } from 'phoenix'
import { usePhoenixService } from '@/services/phoenix-service'
import type { ActivityEvent, ActivityLogFilters } from '@/types/activity-log'
import { EVENT_TYPES } from '@/types/activity-log'

interface EventPayload {
  timestamp: string
  data: {
    id?: string
    user_id?: string
    user_login?: string
    user_name?: string
    message?: string
    bits?: number
    tier?: number
    correlation_id?: string
  }
}

export function useActivityLog() {
  const { socket, isConnected } = usePhoenixService()
  const [events, setEvents] = createSignal<ActivityEvent[]>([])
  const [loading] = createSignal(false)
  const [error] = createSignal(null)
  const [hasMore] = createSignal(false)
  const [filters, setFilters] = createSignal<ActivityLogFilters>({ limit: 50 })
  const [eventsChannel, setEventsChannel] = createSignal<Channel | null>(null)

  const addEvent = (event: ActivityEvent) => {
    setEvents((prev) => [event, ...prev].slice(0, 1000))
  }

  const transformUnifiedEvent = (event: any): ActivityEvent | null => {
    if (!event || !event.type || !event.data) return null

    return {
      id: event.id || crypto.randomUUID(),
      timestamp: event.timestamp || new Date().toISOString(),
      event_type: event.type,
      user_id: event.data.user_id || null,
      user_login: event.data.user_login || null,
      user_name: event.data.user_name || null,
      data: event.data,
      correlation_id: event.meta?.correlation_id || null
    }
  }

  createEffect(() => {
    const connected = isConnected()
    const phoenixSocket = socket()

    if (connected && phoenixSocket && !eventsChannel()) {
      const channel = phoenixSocket.channel('events:all', {})

      channel.on('unified_event', (event: any) => {
        const activityEvent = transformUnifiedEvent(event)
        if (activityEvent) addEvent(activityEvent)
      })

      channel.join()
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
    loadMore: () => {}
  }
}
