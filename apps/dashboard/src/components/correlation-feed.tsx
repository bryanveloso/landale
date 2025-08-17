/**
 * Correlation Feed Component
 *
 * Real-time feed of correlation events with live updates.
 * Shows correlations as they happen with animated notifications.
 */

import { Show, For, createSignal, createEffect } from 'solid-js'
import { useCorrelationChannel } from '@/hooks/use-correlation-channel'
import type { Correlation } from '@/hooks/use-correlation-channel'

interface FeedItem extends Correlation {
  isNew?: boolean
  fadeOut?: boolean
}

export function CorrelationFeed() {
  const { correlations, metrics, isConnected } = useCorrelationChannel()
  const [feedItems, setFeedItems] = createSignal<FeedItem[]>([])
  const [autoScroll, setAutoScroll] = createSignal(true)

  let feedRef: HTMLDivElement | undefined

  // Update feed when new correlations arrive
  createEffect(() => {
    const newCorrelations = correlations
    if (newCorrelations.length === 0) return

    setFeedItems((prev) => {
      // Mark new items
      const prevIds = new Set(prev.map((item) => item.id))
      const updated = newCorrelations.map((correlation) => ({
        ...correlation,
        isNew: !prevIds.has(correlation.id),
        fadeOut: false
      }))

      // Limit to last 50 items
      const limited = updated.slice(0, 50)

      // Auto-scroll to bottom if enabled
      if (autoScroll() && feedRef) {
        setTimeout(() => {
          feedRef.scrollTop = feedRef.scrollHeight
        }, 100)
      }

      return limited
    })

    // Remove "new" flag after animation
    setTimeout(() => {
      setFeedItems((prev) => prev.map((item) => ({ ...item, isNew: false })))
    }, 2000)
  })

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffSeconds = Math.floor(diffMs / 1000)
    const diffMinutes = Math.floor(diffSeconds / 60)
    const diffHours = Math.floor(diffMinutes / 60)

    if (diffSeconds < 60) {
      return `${diffSeconds}s ago`
    } else if (diffMinutes < 60) {
      return `${diffMinutes}m ago`
    } else if (diffHours < 24) {
      return `${diffHours}h ago`
    } else {
      return date.toLocaleDateString()
    }
  }

  const getPatternColor = (pattern: string) => {
    switch (pattern) {
      case 'direct_quote':
        return 'border-green-500 bg-green-500/10'
      case 'keyword_echo':
        return 'border-blue-500 bg-blue-500/10'
      case 'emote_reaction':
        return 'border-yellow-500 bg-yellow-500/10'
      case 'question_response':
        return 'border-purple-500 bg-purple-500/10'
      case 'temporal_only':
        return 'border-gray-500 bg-gray-500/10'
      default:
        return 'border-gray-400 bg-gray-400/10'
    }
  }

  const getPatternIcon = (pattern: string) => {
    switch (pattern) {
      case 'direct_quote':
        return '💬'
      case 'keyword_echo':
        return '📢'
      case 'emote_reaction':
        return '😄'
      case 'question_response':
        return '❓'
      case 'temporal_only':
        return '⏱️'
      default:
        return '🔗'
    }
  }

  const getConfidenceColor = (confidence: number) => {
    if (confidence >= 0.8) return 'text-green-400'
    if (confidence >= 0.6) return 'text-yellow-400'
    return 'text-red-400'
  }

  const handleScroll = () => {
    if (!feedRef) return

    const { scrollTop, scrollHeight, clientHeight } = feedRef
    const isAtBottom = scrollTop + clientHeight >= scrollHeight - 50

    setAutoScroll(isAtBottom)
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <div class="mb-2 flex items-center justify-between">
        <h3 class="text-xs font-medium text-gray-300">Live Correlation Feed</h3>
        <div class="flex items-center gap-2">
          <Show when={metrics}>
            <span class="font-mono text-xs text-gray-400">
              {(metrics!.correlations_per_minute || 0).toFixed(1)}/min
            </span>
          </Show>
          <button
            class={`rounded px-2 py-1 text-xs transition-colors ${
              autoScroll() ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
            onClick={() => setAutoScroll(!autoScroll())}
            title={autoScroll() ? 'Auto-scroll enabled' : 'Auto-scroll disabled'}>
            {autoScroll() ? '📌' : '📍'}
          </button>
        </div>
      </div>

      <Show
        when={isConnected && feedItems().length > 0}
        fallback={
          <div class="flex h-32 items-center justify-center text-xs text-gray-500">
            <Show when={!isConnected} fallback={<span>Waiting for correlations...</span>}>
              <span class="text-red-400">Disconnected from feed</span>
            </Show>
          </div>
        }>
        <div
          ref={feedRef}
          class="scrollbar-thin scrollbar-track-gray-800 scrollbar-thumb-gray-600 h-96 space-y-2 overflow-y-auto"
          onScroll={handleScroll}>
          <For each={feedItems()}>
            {(item) => (
              <div
                class={`relative rounded border-l-2 p-2 text-xs transition-all duration-500 ${getPatternColor(item.pattern_type)} ${item.isNew ? 'scale-105 animate-pulse shadow-lg' : 'scale-100'} ${item.fadeOut ? 'opacity-50' : 'opacity-100'} `}>
                {/* New indicator */}
                <Show when={item.isNew}>
                  <div class="absolute -top-1 -right-1 h-2 w-2 animate-ping rounded-full bg-red-500" />
                </Show>

                <div class="mb-1 flex items-center justify-between">
                  <div class="flex items-center gap-1">
                    <span class="text-sm">{getPatternIcon(item.pattern_type)}</span>
                    <span class="font-medium text-gray-200">{item.pattern_type.replace('_', ' ')}</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class={`font-mono ${getConfidenceColor(item.confidence)}`}>
                      {Math.round(item.confidence * 100)}%
                    </span>
                    <span class="text-gray-500">{formatTimestamp(item.created_at)}</span>
                  </div>
                </div>

                <div class="space-y-1">
                  <div class="rounded bg-gray-800/50 p-1">
                    <span class="text-gray-400">Stream:</span>
                    <span class="ml-1 text-gray-200">{item.transcription_text}</span>
                  </div>

                  <div class="rounded bg-gray-800/50 p-1">
                    <span class="text-blue-400">{item.chat_user}:</span>
                    <span class="ml-1 text-gray-200">{item.chat_text}</span>
                  </div>
                </div>

                <Show when={item.detected_keywords.length > 0}>
                  <div class="mt-1 flex flex-wrap gap-1">
                    <For each={item.detected_keywords.slice(0, 3)}>
                      {(keyword) => <span class="rounded bg-blue-600/20 px-1 text-blue-300">{keyword}</span>}
                    </For>
                    <Show when={item.detected_keywords.length > 3}>
                      <span class="text-gray-500">+{item.detected_keywords.length - 3}</span>
                    </Show>
                  </div>
                </Show>

                <div class="mt-1 text-gray-500">+{Math.round(item.time_offset_ms / 1000)}s response time</div>
              </div>
            )}
          </For>
        </div>

        {/* Feed controls */}
        <div class="mt-2 flex items-center justify-between border-t border-gray-700 pt-2">
          <div class="text-xs text-gray-500">{feedItems().length} correlations shown</div>
          <div class="flex gap-2">
            <button
              class="rounded bg-gray-700 px-2 py-1 text-xs text-gray-300 transition-colors hover:bg-gray-600"
              onClick={() => {
                if (feedRef) {
                  feedRef.scrollTop = feedRef.scrollHeight
                  setAutoScroll(true)
                }
              }}>
              ⬇ Bottom
            </button>
            <button
              class="rounded bg-gray-700 px-2 py-1 text-xs text-gray-300 transition-colors hover:bg-gray-600"
              onClick={() => {
                if (feedRef) {
                  feedRef.scrollTop = 0
                  setAutoScroll(false)
                }
              }}>
              ⬆ Top
            </button>
          </div>
        </div>
      </Show>
    </div>
  )
}
