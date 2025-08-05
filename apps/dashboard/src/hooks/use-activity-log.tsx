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

  const transformEvent = (type: string, payload: EventPayload): ActivityEvent | null => {
    const baseEvent = {
      id: payload.data?.id || crypto.randomUUID(),
      timestamp: payload.timestamp || new Date().toISOString(),
      user_id: payload.data?.user_id || null,
      user_login: payload.data?.user_login || null,
      user_name: payload.data?.user_name || null,
      correlation_id: null
    }

    switch (type) {
      case 'chat_message':
        return {
          ...baseEvent,
          event_type: EVENT_TYPES.CHAT_MESSAGE,
          data: { message: payload.data?.message || '' }
        }
      case 'follower':
        return { ...baseEvent, event_type: EVENT_TYPES.FOLLOW, data: {} }
      case 'subscription':
        return {
          ...baseEvent,
          event_type: EVENT_TYPES.SUBSCRIBE,
          data: { tier: payload.data?.tier || 1 }
        }
      case 'cheer':
        return {
          ...baseEvent,
          event_type: EVENT_TYPES.CHEER,
          data: { bits: payload.data?.bits || 0 }
        }
      default:
        return null
    }
  }

  createEffect(() => {
    const connected = isConnected()
    const phoenixSocket = socket()

    if (connected && phoenixSocket && !eventsChannel()) {
      const channel = phoenixSocket.channel('events:all', {})

      channel.on('chat_message', (payload: EventPayload) => {
        const event = transformEvent('chat_message', payload)
        if (event) addEvent(event)
      })

      channel.on('follower', (payload: EventPayload) => {
        const event = transformEvent('follower', payload)
        if (event) addEvent(event)
      })

      channel.on('subscription', (payload: EventPayload) => {
        const event = transformEvent('subscription', payload)
        if (event) addEvent(event)
      })

      channel.on('cheer', (payload: EventPayload) => {
        const event = transformEvent('cheer', payload)
        if (event) addEvent(event)
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
