/**
 * Transcription Analytics Component
 *
 * Displays comprehensive transcription accuracy monitoring and Whisper training insights.
 * Shows confidence scores, accuracy trends, and performance metrics.
 */

import { Show, For } from 'solid-js'
import { useServiceStatus } from '@/services/service-status-service'

export function TranscriptionAnalytics() {
  const { transcriptionAnalytics } = useServiceStatus()

  const formatDuration = (seconds: number) => {
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const secs = Math.floor(seconds % 60)

    if (hours > 0) {
      return `${hours}h ${minutes}m ${secs}s`
    } else if (minutes > 0) {
      return `${minutes}m ${secs}s`
    } else {
      return `${secs}s`
    }
  }

  const getConfidenceColor = (confidence: number) => {
    if (confidence >= 0.8) return 'text-green-400'
    if (confidence >= 0.6) return 'text-yellow-400'
    return 'text-red-400'
  }

  const getTrendColor = (trend: string) => {
    switch (trend) {
      case 'improving':
        return 'text-green-400'
      case 'declining':
        return 'text-red-400'
      case 'stable':
        return 'text-blue-400'
      default:
        return 'text-gray-400'
    }
  }

  const getQualityColor = (quality: string) => {
    switch (quality) {
      case 'excellent':
        return 'text-green-400'
      case 'good':
        return 'text-blue-400'
      case 'acceptable':
        return 'text-yellow-400'
      case 'needs_attention':
        return 'text-red-400'
      default:
        return 'text-gray-400'
    }
  }

  const getTrendIcon = (trend: string) => {
    switch (trend) {
      case 'improving':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
          </svg>
        )
      case 'declining':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 17h8m0 0V9m0 8l-8-8-4 4-6-6" />
          </svg>
        )
      case 'stable':
        return (
          <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4" />
          </svg>
        )
      default:
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
    }
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <h3 class="mb-2 text-xs font-medium text-gray-300">Transcription Analytics</h3>

      <Show
        when={transcriptionAnalytics() && !transcriptionAnalytics()?.error ? transcriptionAnalytics() : null}
        fallback={
          <div class="text-xs text-gray-500">
            <Show when={transcriptionAnalytics()?.error} fallback={<span>Loading analytics...</span>}>
              <span class="text-red-400">Analytics unavailable: {transcriptionAnalytics()?.error}</span>
            </Show>
          </div>
        }>
        {(analytics) => (
          <div class="space-y-3 text-xs">
            {/* Volume & Performance Overview */}
            <div class="space-y-1">
              <div class="flex justify-between">
                <span class="text-gray-400">24h Transcriptions:</span>
                <span class="font-mono text-gray-300">{analytics().total_transcriptions_24h}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">Total Duration:</span>
                <span class="font-mono text-gray-300">{formatDuration(analytics().duration.total_seconds)}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">Avg Length:</span>
                <span class="font-mono text-gray-300">{analytics().duration.average_duration.toFixed(1)}s</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">Text Volume:</span>
                <span class="font-mono text-gray-300">
                  {analytics().duration.total_text_length.toLocaleString()} chars
                </span>
              </div>
            </div>

            {/* Confidence Metrics */}
            <div class="border-t border-gray-800 pt-2">
              <div class="mb-1 text-xs font-medium text-gray-300">Confidence Scores</div>
              <div class="space-y-1">
                <div class="flex justify-between">
                  <span class="text-gray-400">Average:</span>
                  <span class={`font-mono ${getConfidenceColor(analytics().confidence.average)}`}>
                    {(analytics().confidence.average * 100).toFixed(1)}%
                  </span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">Range:</span>
                  <span class="font-mono text-gray-300">
                    {(analytics().confidence.min * 100).toFixed(1)}% - {(analytics().confidence.max * 100).toFixed(1)}%
                  </span>
                </div>
              </div>

              {/* Confidence Distribution */}
              <div class="mt-2">
                <div class="mb-1 text-xs text-gray-400">Distribution:</div>
                <div class="flex gap-2 text-xs">
                  <div class="flex items-center gap-1">
                    <div class="h-2 w-2 rounded-full bg-green-500" />
                    <span class="text-gray-400">High: {analytics().confidence.distribution.high}</span>
                  </div>
                  <div class="flex items-center gap-1">
                    <div class="h-2 w-2 rounded-full bg-yellow-500" />
                    <span class="text-gray-400">Med: {analytics().confidence.distribution.medium}</span>
                  </div>
                  <div class="flex items-center gap-1">
                    <div class="h-2 w-2 rounded-full bg-red-500" />
                    <span class="text-gray-400">Low: {analytics().confidence.distribution.low}</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Trends & Quality */}
            <div class="border-t border-gray-800 pt-2">
              <div class="mb-1 text-xs font-medium text-gray-300">Quality Trends</div>
              <div class="space-y-1">
                <div class="flex items-center justify-between">
                  <span class="text-gray-400">Confidence:</span>
                  <div class={`flex items-center gap-1 ${getTrendColor(analytics().trends.confidence_trend)}`}>
                    {getTrendIcon(analytics().trends.confidence_trend)}
                    <span class="capitalize">{analytics().trends.confidence_trend}</span>
                  </div>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">Overall Quality:</span>
                  <span class={`capitalize ${getQualityColor(analytics().trends.quality_trend)}`}>
                    {analytics().trends.quality_trend.replace('_', ' ')}
                  </span>
                </div>
              </div>
            </div>

            {/* Recent Volume Chart (simplified) */}
            <Show when={analytics().trends.hourly_volume.length > 0}>
              <div class="border-t border-gray-800 pt-2">
                <div class="mb-1 text-xs font-medium text-gray-300">Recent Activity</div>
                <div class="flex h-8 items-end gap-px">
                  <For each={analytics().trends.hourly_volume.slice(-12)}>
                    {(hour) => {
                      const maxCount = Math.max(...analytics().trends.hourly_volume.map((h: any) => h.count))
                      const height = maxCount > 0 ? Math.max((hour.count / maxCount) * 100, 2) : 2
                      return (
                        <div
                          class="flex-1 rounded-sm bg-blue-500 opacity-70 transition-opacity hover:opacity-100"
                          style={{ height: `${height}%` }}
                          title={`${hour.count} transcriptions at ${new Date(hour.hour).toLocaleTimeString()}`}
                        />
                      )
                    }}
                  </For>
                </div>
                <div class="mt-1 text-xs text-gray-500">Last 12 hours</div>
              </div>
            </Show>
          </div>
        )}
      </Show>
    </div>
  )
}
