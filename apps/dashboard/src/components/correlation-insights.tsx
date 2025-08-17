/**
 * Correlation Insights Component
 *
 * Main dashboard widget displaying real-time correlations between chat messages and transcriptions.
 * Shows recent correlations with pattern types, confidence scores, and timing information.
 */

import { Show, For, createSignal, onMount } from 'solid-js'
import { useCorrelationChannel } from '@/hooks/use-correlation-channel'
import type { Correlation } from '@/hooks/use-correlation-channel'

export function CorrelationInsights() {
  const { correlations, metrics, engineStatus, isConnected, requestRecentCorrelations } = useCorrelationChannel()

  const [selectedCorrelation, setSelectedCorrelation] = createSignal<Correlation | null>(null)

  // Refresh data periodically
  onMount(() => {
    const interval = setInterval(() => {
      if (isConnected) {
        requestRecentCorrelations()
      }
    }, 30000) // Refresh every 30 seconds

    return () => clearInterval(interval)
  })

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp)
    return date.toLocaleTimeString('en-US', {
      hour12: false,
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    })
  }

  const formatTimeOffset = (offsetMs: number) => {
    const seconds = Math.round(offsetMs / 1000)
    return `+${seconds}s`
  }

  const getPatternColor = (pattern: string) => {
    switch (pattern) {
      case 'direct_quote':
        return 'text-green-400'
      case 'keyword_echo':
        return 'text-blue-400'
      case 'emote_reaction':
        return 'text-yellow-400'
      case 'question_response':
        return 'text-purple-400'
      case 'temporal_only':
        return 'text-gray-400'
      default:
        return 'text-gray-300'
    }
  }

  const getPatternIcon = (pattern: string) => {
    switch (pattern) {
      case 'direct_quote':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
            />
          </svg>
        )
      case 'keyword_echo':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
            />
          </svg>
        )
      case 'emote_reaction':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        )
      case 'question_response':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        )
      case 'temporal_only':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        )
      default:
        return null
    }
  }

  const getConfidenceColor = (confidence: number) => {
    if (confidence >= 0.8) return 'text-green-400'
    if (confidence >= 0.6) return 'text-yellow-400'
    return 'text-red-400'
  }

  const formatPatternType = (pattern: string) => {
    return pattern.replace('_', ' ').replace(/\b\w/g, (l) => l.toUpperCase())
  }

  const truncateText = (text: string, maxLength = 60) => {
    if (text.length <= maxLength) return text
    return text.substring(0, maxLength) + '...'
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <div class="mb-2 flex items-center justify-between">
        <h3 class="text-xs font-medium text-gray-300">Correlation Insights</h3>
        <div class="flex items-center gap-2">
          <Show when={!isConnected}>
            <div class="h-2 w-2 rounded-full bg-red-500" title="Disconnected" />
          </Show>
          <Show when={isConnected}>
            <div class="h-2 w-2 rounded-full bg-green-500" title="Connected" />
          </Show>
          <Show when={metrics}>
            <span class="font-mono text-xs text-gray-400">{metrics!.correlation_count} total</span>
          </Show>
        </div>
      </div>

      <Show
        when={isConnected && correlations.length > 0}
        fallback={
          <div class="text-xs text-gray-500">
            <Show when={!isConnected} fallback={<span>No correlations detected yet...</span>}>
              <span class="text-red-400">Disconnected from correlation engine</span>
            </Show>
          </div>
        }>
        {/* Quick Stats */}
        <Show when={engineStatus}>
          <div class="mb-3 grid grid-cols-3 gap-2 text-xs">
            <div class="text-center">
              <div class="font-mono text-blue-400">{engineStatus!.transcription_count}</div>
              <div class="text-gray-500">Transcripts</div>
            </div>
            <div class="text-center">
              <div class="font-mono text-green-400">{engineStatus!.chat_count}</div>
              <div class="text-gray-500">Messages</div>
            </div>
            <div class="text-center">
              <div class="font-mono text-yellow-400">{engineStatus!.correlation_count}</div>
              <div class="text-gray-500">Matches</div>
            </div>
          </div>
        </Show>

        {/* Recent Correlations List */}
        <div class="space-y-2">
          <div class="text-xs font-medium text-gray-400">Recent Correlations</div>
          <div class="max-h-64 space-y-1 overflow-y-auto">
            <For each={correlations.slice(0, 10)}>
              {(correlation) => (
                <div
                  class="hover:bg-gray-750 cursor-pointer rounded border border-gray-700 bg-gray-800 p-2 text-xs transition-colors"
                  onClick={() => setSelectedCorrelation(correlation)}>
                  <div class="mb-1 flex items-center justify-between">
                    <div class="flex items-center gap-1">
                      <div class={getPatternColor(correlation.pattern_type)}>
                        {getPatternIcon(correlation.pattern_type)}
                      </div>
                      <span class={`text-xs ${getPatternColor(correlation.pattern_type)}`}>
                        {formatPatternType(correlation.pattern_type)}
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <span class={`font-mono text-xs ${getConfidenceColor(correlation.confidence)}`}>
                        {Math.round(correlation.confidence * 100)}%
                      </span>
                      <span class="font-mono text-xs text-gray-400">
                        {formatTimeOffset(correlation.time_offset_ms)}
                      </span>
                    </div>
                  </div>

                  <div class="space-y-1">
                    <div class="text-gray-300">
                      <span class="text-gray-500">Stream:</span> {truncateText(correlation.transcription_text)}
                    </div>
                    <div class="text-gray-300">
                      <span class="text-gray-500">{correlation.chat_user}:</span> {truncateText(correlation.chat_text)}
                    </div>
                  </div>

                  <div class="mt-1 text-xs text-gray-500">{formatTimestamp(correlation.created_at)}</div>
                </div>
              )}
            </For>
          </div>
        </div>
      </Show>

      {/* Detailed Modal */}
      <Show when={selectedCorrelation()}>
        <div
          class="bg-opacity-50 fixed inset-0 z-50 flex items-center justify-center bg-black"
          onClick={() => setSelectedCorrelation(null)}>
          <div class="w-96 rounded-lg border border-gray-600 bg-gray-800 p-4" onClick={(e) => e.stopPropagation()}>
            <div class="mb-3 flex items-center justify-between">
              <h4 class="text-sm font-medium text-gray-200">Correlation Details</h4>
              <button class="text-gray-400 hover:text-gray-200" onClick={() => setSelectedCorrelation(null)}>
                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <div class="space-y-3 text-xs">
              <div>
                <div class="mb-1 text-gray-400">Pattern Type:</div>
                <div class={`flex items-center gap-1 ${getPatternColor(selectedCorrelation()!.pattern_type)}`}>
                  {getPatternIcon(selectedCorrelation()!.pattern_type)}
                  <span>{formatPatternType(selectedCorrelation()!.pattern_type)}</span>
                </div>
              </div>

              <div>
                <div class="mb-1 text-gray-400">Confidence & Timing:</div>
                <div class="flex justify-between">
                  <span class={getConfidenceColor(selectedCorrelation()!.confidence)}>
                    {Math.round(selectedCorrelation()!.confidence * 100)}% confidence
                  </span>
                  <span class="text-gray-300">{formatTimeOffset(selectedCorrelation()!.time_offset_ms)} delay</span>
                </div>
              </div>

              <div>
                <div class="mb-1 text-gray-400">Stream Transcription:</div>
                <div class="rounded bg-gray-700 p-2 text-gray-200">{selectedCorrelation()!.transcription_text}</div>
              </div>

              <div>
                <div class="mb-1 text-gray-400">Chat Response:</div>
                <div class="rounded bg-gray-700 p-2 text-gray-200">
                  <span class="text-blue-400">{selectedCorrelation()!.chat_user}:</span>{' '}
                  {selectedCorrelation()!.chat_text}
                </div>
              </div>

              <Show when={selectedCorrelation()!.detected_keywords.length > 0}>
                <div>
                  <div class="mb-1 text-gray-400">Detected Keywords:</div>
                  <div class="flex flex-wrap gap-1">
                    <For each={selectedCorrelation()!.detected_keywords}>
                      {(keyword) => <span class="rounded bg-blue-600 px-1 py-0.5 text-xs text-white">{keyword}</span>}
                    </For>
                  </div>
                </div>
              </Show>

              <div class="border-t border-gray-600 pt-2 text-gray-500">
                Detected at {formatTimestamp(selectedCorrelation()!.created_at)}
              </div>
            </div>
          </div>
        </div>
      </Show>
    </div>
  )
}
