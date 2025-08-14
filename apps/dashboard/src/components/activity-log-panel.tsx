import { Show, For, createMemo } from 'solid-js'
import { Button } from './ui/button'
import { useActivityLog } from '@/hooks/use-activity-log'
import type { EventType, ActivityEvent, ChatMessageData, CheerData } from '@/types/activity-log'
import { EVENT_TYPES, EVENT_TYPE_LABELS } from '@/types/activity-log'

export function ActivityLogPanel() {
  const { events, loading, error, filters, hasMore, applyFilters, clearFilters, loadMore } = useActivityLog()

  const handleFilterChange = (eventType?: EventType) => {
    applyFilters({
      ...filters(),
      event_type: eventType
    })
  }

  const formatEventTime = (timestamp: string) => {
    return new Date(timestamp).toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const formatEventContent = (event: ActivityEvent) => {
    // Handle flat event format where data properties are directly on the event
    const eventData = event.data as Record<string, unknown>

    switch (event.event_type) {
      case EVENT_TYPES.CHAT_MESSAGE: {
        // In flat format, message is directly in the data object
        const message = eventData.message || (eventData as ChatMessageData).message
        return `${event.user_name}: ${message}`
      }

      case EVENT_TYPES.FOLLOW:
        return `${event.user_name} followed`

      case EVENT_TYPES.SUBSCRIBE:
        return `${event.user_name} subscribed`

      case EVENT_TYPES.CHEER: {
        // In flat format, bits is directly in the data object
        const bits = eventData.bits || eventData.cheer_bits || (eventData as CheerData).bits
        return `${event.user_name} cheered ${bits} bits`
      }

      case EVENT_TYPES.STREAM_ONLINE:
        return 'Stream went online'

      case EVENT_TYPES.STREAM_OFFLINE:
        return 'Stream went offline'

      default:
        return `${event.event_type} event`
    }
  }

  const filteredEvents = createMemo(() => {
    const currentFilters = filters()
    const eventList = events()

    if (!currentFilters.event_type) {
      return eventList.slice(0, currentFilters.limit || 50)
    }

    return eventList
      .filter((event) => event.event_type === currentFilters.event_type)
      .slice(0, currentFilters.limit || 50)
  })

  return (
    <section>
      <header>
        <h2>Activity Log</h2>

        <div>
          <Button onClick={clearFilters}>All Events</Button>
          <Button onClick={() => handleFilterChange(EVENT_TYPES.CHAT_MESSAGE)}>Chat</Button>
          <Button onClick={() => handleFilterChange(EVENT_TYPES.FOLLOW)}>Follows</Button>
          <Button onClick={() => handleFilterChange(EVENT_TYPES.SUBSCRIBE)}>Subscriptions</Button>
          <Button onClick={() => handleFilterChange(EVENT_TYPES.CHEER)}>Cheers</Button>
        </div>
      </header>

      <Show when={error()}>
        <div>Error: {error()}</div>
      </Show>

      <Show when={loading()}>
        <div>Loading events...</div>
      </Show>

      <Show when={filteredEvents().length > 0}>
        <ul>
          <For each={filteredEvents()}>
            {(event) => (
              <li>
                <time>{formatEventTime(event.timestamp)}</time>
                <span>{formatEventContent(event)}</span>
                <small>{EVENT_TYPE_LABELS[event.event_type as EventType] || event.event_type}</small>
              </li>
            )}
          </For>
        </ul>
      </Show>

      <Show when={!loading() && filteredEvents().length === 0}>
        <div>
          <p>No events found</p>
          <Show when={filters().event_type}>
            <Button onClick={clearFilters}>Clear filters</Button>
          </Show>
        </div>
      </Show>

      <Show when={hasMore() && !loading()}>
        <Button onClick={loadMore}>Load More</Button>
      </Show>

      {/* Debug info for development */}
      {import.meta.env.DEV && (
        <div>
          <div>Total Events: {events().length}</div>
          <div>Filtered Events: {filteredEvents().length}</div>
          <div>Active Filter: {filters().event_type || 'None'}</div>
        </div>
      )}
    </section>
  )
}
