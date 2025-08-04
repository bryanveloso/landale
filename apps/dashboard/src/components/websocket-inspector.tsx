/**
 * WebSocket Message Inspector Component
 *
 * Visual interface for debugging WebSocket communication with Phoenix channels.
 */

import { createSignal, For, Show, onMount, onCleanup } from 'solid-js'
import { useStreamService } from '@/services/stream-service'
import type { WebSocketMessage, MessageFilter } from '@landale/shared/websocket'

export function WebSocketInspector() {
  const { getSocket } = useStreamService()

  const [messages, setMessages] = createSignal<WebSocketMessage[]>([])
  const [filter, setFilter] = createSignal<MessageFilter>({})
  const [isEnabled, setIsEnabled] = createSignal(false)
  const [isPaused, setIsPaused] = createSignal(false)
  const [selectedMessage, setSelectedMessage] = createSignal<WebSocketMessage | null>(null)

  let unsubscribe: (() => void) | null = null

  onMount(() => {
    const socket = getSocket()
    if (socket) {
      const inspector = socket.getMessageInspector()

      // Subscribe to new messages
      unsubscribe = inspector.subscribe((message) => {
        if (!isPaused()) {
          setMessages((prev) => [...prev, message].slice(-100)) // Keep last 100
        }
      })

      // Load existing messages
      setMessages(inspector.getMessages())
      setIsEnabled(inspector.isEnabled())
    }
  })

  onCleanup(() => {
    if (unsubscribe) {
      unsubscribe()
    }
  })

  const toggleInspection = () => {
    const socket = getSocket()
    if (socket) {
      const newState = !isEnabled()
      socket.enableMessageInspection(newState)
      setIsEnabled(newState)

      if (!newState) {
        setMessages([])
      }
    }
  }

  const clearMessages = () => {
    const socket = getSocket()
    if (socket) {
      socket.getMessageInspector().clear()
      setMessages([])
    }
  }

  const exportMessages = () => {
    const socket = getSocket()
    if (socket) {
      const json = socket.getMessageInspector().exportAsJson()
      const blob = new Blob([json], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `websocket-messages-${Date.now()}.json`
      a.click()
      URL.revokeObjectURL(url)
    }
  }

  const filteredMessages = () => {
    const currentFilter = filter()
    const allMessages = messages()

    if (!currentFilter.direction && !currentFilter.channel && !currentFilter.event && !currentFilter.search) {
      return allMessages
    }

    return allMessages.filter((msg) => {
      if (currentFilter.direction && currentFilter.direction !== 'both' && msg.direction !== currentFilter.direction) {
        return false
      }
      if (currentFilter.channel && msg.channel !== currentFilter.channel) {
        return false
      }
      if (currentFilter.event && msg.event !== currentFilter.event) {
        return false
      }
      if (currentFilter.search && msg.raw && !msg.raw.toLowerCase().includes(currentFilter.search.toLowerCase())) {
        return false
      }
      return true
    })
  }

  const formatTimestamp = (timestamp: number) => {
    const date = new Date(timestamp)
    return date.toLocaleTimeString('en-US', {
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      fractionalSecondDigits: 3
    })
  }

  const getMessageClass = (msg: WebSocketMessage) => {
    const base = 'px-2 py-1 font-mono text-xs cursor-pointer hover:bg-gray-800 border-l-2'
    const directionClass = msg.direction === 'incoming' ? 'border-green-500' : 'border-blue-500'
    const selectedClass = selectedMessage()?.id === msg.id ? 'bg-gray-800' : ''
    return `${base} ${directionClass} ${selectedClass}`
  }

  return (
    <div class="flex h-full flex-col bg-gray-950 text-gray-300">
      {/* Header */}
      <div class="flex items-center justify-between border-b border-gray-800 bg-gray-900 px-3 py-2">
        <h3 class="text-xs font-medium">WebSocket Inspector</h3>
        <div class="flex items-center gap-2">
          <button
            onClick={toggleInspection}
            class={`rounded px-2 py-1 text-xs ${
              isEnabled() ? 'bg-green-600 text-white hover:bg-green-700' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}>
            {isEnabled() ? 'Enabled' : 'Disabled'}
          </button>
          <button
            onClick={() => setIsPaused(!isPaused())}
            class="rounded bg-gray-700 px-2 py-1 text-xs hover:bg-gray-600"
            disabled={!isEnabled()}>
            {isPaused() ? 'Resume' : 'Pause'}
          </button>
          <button onClick={clearMessages} class="rounded bg-gray-700 px-2 py-1 text-xs hover:bg-gray-600">
            Clear
          </button>
          <button onClick={exportMessages} class="rounded bg-gray-700 px-2 py-1 text-xs hover:bg-gray-600">
            Export
          </button>
        </div>
      </div>

      {/* Filters */}
      <div class="border-b border-gray-800 bg-gray-900 px-3 py-2">
        <div class="flex gap-2">
          <select
            class="rounded bg-gray-800 px-2 py-1 text-xs"
            value={filter().direction || 'both'}
            onChange={(e) => setFilter((prev) => ({ ...prev, direction: e.target.value as any }))}>
            <option value="both">All</option>
            <option value="incoming">Incoming</option>
            <option value="outgoing">Outgoing</option>
          </select>

          <input
            type="text"
            placeholder="Channel"
            class="rounded bg-gray-800 px-2 py-1 text-xs"
            value={filter().channel || ''}
            onChange={(e) => setFilter((prev) => ({ ...prev, channel: e.target.value }))}
          />

          <input
            type="text"
            placeholder="Event"
            class="rounded bg-gray-800 px-2 py-1 text-xs"
            value={filter().event || ''}
            onChange={(e) => setFilter((prev) => ({ ...prev, event: e.target.value }))}
          />

          <input
            type="text"
            placeholder="Search..."
            class="flex-1 rounded bg-gray-800 px-2 py-1 text-xs"
            value={filter().search || ''}
            onChange={(e) => setFilter((prev) => ({ ...prev, search: e.target.value }))}
          />
        </div>
      </div>

      {/* Message List */}
      <div class="flex flex-1 overflow-hidden">
        <div class="w-1/2 overflow-y-auto border-r border-gray-800">
          <Show
            when={isEnabled()}
            fallback={
              <div class="p-4 text-center text-xs text-gray-500">Enable inspection to start capturing messages</div>
            }>
            <Show
              when={filteredMessages().length > 0}
              fallback={<div class="p-4 text-center text-xs text-gray-500">No messages captured yet</div>}>
              <For each={filteredMessages()}>
                {(msg) => (
                  <div class={getMessageClass(msg)} onClick={() => setSelectedMessage(msg)}>
                    <div class="flex items-center gap-2">
                      <span class="text-gray-500">{formatTimestamp(msg.timestamp)}</span>
                      <span class={msg.direction === 'incoming' ? 'text-green-400' : 'text-blue-400'}>
                        {msg.direction === 'incoming' ? '←' : '→'}
                      </span>
                      <Show when={msg.channel}>
                        <span class="text-purple-400">{msg.channel}</span>
                      </Show>
                      <Show when={msg.event}>
                        <span class="text-yellow-400">{msg.event}</span>
                      </Show>
                    </div>
                  </div>
                )}
              </For>
            </Show>
          </Show>
        </div>

        {/* Message Detail */}
        <div class="w-1/2 overflow-y-auto p-3">
          <Show
            when={selectedMessage()}
            fallback={<div class="text-center text-xs text-gray-500">Select a message to view details</div>}>
            {(msg) => (
              <div class="space-y-2">
                <div>
                  <span class="text-xs text-gray-500">Timestamp:</span>
                  <div class="font-mono text-xs">{new Date(msg().timestamp).toISOString()}</div>
                </div>

                <div>
                  <span class="text-xs text-gray-500">Direction:</span>
                  <div class="font-mono text-xs">{msg().direction}</div>
                </div>

                <Show when={msg().channel}>
                  <div>
                    <span class="text-xs text-gray-500">Channel:</span>
                    <div class="font-mono text-xs">{msg().channel}</div>
                  </div>
                </Show>

                <Show when={msg().event}>
                  <div>
                    <span class="text-xs text-gray-500">Event:</span>
                    <div class="font-mono text-xs">{msg().event}</div>
                  </div>
                </Show>

                <Show when={msg().topic}>
                  <div>
                    <span class="text-xs text-gray-500">Topic:</span>
                    <div class="font-mono text-xs">{msg().topic}</div>
                  </div>
                </Show>

                <Show when={msg().payload}>
                  <div>
                    <span class="text-xs text-gray-500">Payload:</span>
                    <pre class="mt-1 rounded bg-gray-900 p-2 font-mono text-xs">
                      {JSON.stringify(msg().payload, null, 2)}
                    </pre>
                  </div>
                </Show>

                <div>
                  <span class="text-xs text-gray-500">Raw:</span>
                  <pre class="mt-1 rounded bg-gray-900 p-2 font-mono text-xs">{msg().raw}</pre>
                </div>
              </div>
            )}
          </Show>
        </div>
      </div>

      {/* Footer Stats */}
      <div class="border-t border-gray-800 bg-gray-900 px-3 py-1">
        <div class="flex items-center justify-between text-xs text-gray-500">
          <span>
            {filteredMessages().length} / {messages().length} messages
          </span>
          <Show when={isPaused()}>
            <span class="text-yellow-500">PAUSED</span>
          </Show>
        </div>
      </div>
    </div>
  )
}
