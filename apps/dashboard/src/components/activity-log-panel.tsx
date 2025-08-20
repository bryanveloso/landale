import { Show, For, createMemo } from 'solid-js'
import { Button } from './ui/button'
import { useActivityLog } from '@/hooks/use-activity-log'
import type { EventType } from '@/types/activity-log'
import { EVENT_TYPES, EVENT_TYPE_LABELS } from '@/types/activity-log'

// Event-specific components
function ChatMessageEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  return (
    <div style="color: #333;">
      <span style="font-weight: bold; color: #0066cc;">{event.user_name}:</span>
      <span style="color: #333; margin-left: 8px;">{event.data?.message || ''}</span>
    </div>
  )
}

function FollowEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  return <div style="color: #28a745; font-weight: bold;">{event.user_name} followed</div>
}

function SubscribeEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  return <div style="color: #6f42c1; font-weight: bold;">{event.user_name} subscribed</div>
}

function CheerEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  const bits = event.data?.bits || event.data?.cheer_bits || 0
  return (
    <div style="color: #fd7e14; font-weight: bold;">
      {event.user_name} cheered {bits} bits
    </div>
  )
}

function StreamOnlineEvent({ jsonData }: { jsonData: string }) {
  return <div style="color: #28a745; font-weight: bold;">Stream went online</div>
}

function StreamOfflineEvent({ jsonData }: { jsonData: string }) {
  return <div style="color: #dc3545; font-weight: bold;">Stream went offline</div>
}

function DefaultEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  return <div style="color: #333;">{event.event_type} event</div>
}

// Component map for each event type
const EVENT_COMPONENTS = {
  [EVENT_TYPES.CHAT_MESSAGE]: ChatMessageEvent,
  [EVENT_TYPES.FOLLOW]: FollowEvent,
  [EVENT_TYPES.SUBSCRIBE]: SubscribeEvent,
  [EVENT_TYPES.CHEER]: CheerEvent,
  [EVENT_TYPES.STREAM_ONLINE]: StreamOnlineEvent,
  [EVENT_TYPES.STREAM_OFFLINE]: StreamOfflineEvent
} as const

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
        <h2 class="sr-only">Activity Log</h2>

        <div class="flex justify-around">
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
            {(event) => {
              const EventComponent = EVENT_COMPONENTS[event.event_type as keyof typeof EVENT_COMPONENTS] || DefaultEvent
              return (
                <li style="margin-bottom: 12px; padding: 8px; border-left: 3px solid #333; background: #f9f9f9; color: #333;">
                  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                    <time style="color: #666; font-size: 12px;">{formatEventTime(event.timestamp)}</time>
                    <small style="color: #888; font-size: 11px;">
                      {EVENT_TYPE_LABELS[event.event_type as EventType] || event.event_type}
                    </small>
                  </div>
                  <EventComponent jsonData={JSON.stringify(event)} />
                  <details style="margin-top: 8px;">
                    <summary style="cursor: pointer; color: #666; font-size: 11px;">JSON Data</summary>
                    <pre style="font-size: 10px; background: #fff; padding: 8px; margin: 4px 0; border-radius: 4px; overflow-x: auto; white-space: pre-wrap; border: 1px solid #ddd;">
                      {JSON.stringify(event, null, 2)}
                    </pre>
                  </details>
                </li>
              )
            }}
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
