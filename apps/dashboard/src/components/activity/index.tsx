import { Show, For, createMemo } from 'solid-js'

import { Button } from '@/components/ui/button'
import { useActivityLog } from '@/hooks/use-activity-log'
import type { EventType } from '@/types/activity-log'
import { EVENT_TYPES, EVENT_TYPE_LABELS } from '@/types/activity-log'

// Emote renderer component
function EmoteRenderer({ fragments }: { fragments: Array<{ type: 'text' | 'emote'; text: string; emote?: any }> }) {
  return (
    <span class="inline-block">
      {fragments.map((fragment, _index) =>
        fragment.type === 'emote' ? (
          <img
            src={
              fragment.emote?.url || `https://static-cdn.jtvnw.net/emoticons/v2/${fragment.emote?.id}/default/dark/1.0`
            }
            alt={fragment.text}
            title={fragment.text}
            style="vertical-align: middle;"
          />
        ) : (
          <span>{fragment.text}</span>
        )
      )}
    </span>
  )
}

// Event-specific components
function ChatMessageEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  const fragments = event.data?.fragments || [{ type: 'text', text: event.data?.message || '' }]

  return (
    <div>
      <span class="font-bold" style={`color: ${event.data.color};`}>
        {event.user_name}:
      </span>
      <span class="ml-2 text-gray-800">
        <EmoteRenderer fragments={fragments} />
      </span>
    </div>
  )
}

function FollowEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  return <div class="font-bold text-green-500">{event.user_name} followed</div>
}

function SubscribeEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  return <div class="font-bold text-purple-600">{event.user_name} subscribed</div>
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
  return <div class="font-bold text-green-500">Stream went online</div>
}

function StreamOfflineEvent({ jsonData }: { jsonData: string }) {
  return <div class="font-bold text-red-500">Stream went offline</div>
}

function DefaultEvent({ jsonData }: { jsonData: string }) {
  const event = JSON.parse(jsonData)
  return <div class="text-gray-800">{event.event_type} event</div>
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
    <section class="h-full">
      <header>
        <h2>Activity Log</h2>
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
                <li>
                  <EventComponent jsonData={JSON.stringify(event)} />
                  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                    <time class="font-mono text-xs">{formatEventTime(event.timestamp)}</time>
                  </div>
                  <details class="mt-2">
                    <summary class="cursor-pointer text-sm text-gray-600">JSON Data</summary>
                    <pre class="my-1 overflow-x-auto rounded border border-gray-300 bg-white p-2 text-xs whitespace-pre-wrap">
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
    </section>
  )
}
