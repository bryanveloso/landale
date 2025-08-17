/**
 * Correlation Metrics Component
 *
 * Displays real-time performance metrics for the correlation engine.
 * Shows processing statistics, health indicators, and system status.
 */

import { Show, createSignal, onMount } from 'solid-js'
import { useCorrelationChannel } from '@/hooks/use-correlation-channel'

export function CorrelationMetrics() {
  const { metrics, engineStatus, isConnected, requestMetrics } = useCorrelationChannel()

  const [previousMetrics, setPreviousMetrics] = createSignal<typeof metrics>(null)

  // Update metrics periodically
  onMount(() => {
    const interval = setInterval(() => {
      if (isConnected) {
        setPreviousMetrics(metrics)
        requestMetrics()
      }
    }, 10000) // Update every 10 seconds

    return () => clearInterval(interval)
  })

  const getHealthColor = (score: number) => {
    if (score >= 0.8) return 'text-green-400'
    if (score >= 0.6) return 'text-yellow-400'
    if (score >= 0.4) return 'text-orange-400'
    return 'text-red-400'
  }

  const getHealthIcon = (score: number) => {
    if (score >= 0.8) {
      return (
        <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
      )
    } else if (score >= 0.6) {
      return (
        <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
          />
        </svg>
      )
    } else {
      return (
        <svg class="h-3 w-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      )
    }
  }

  const getCircuitBreakerColor = (status: string) => {
    switch (status) {
      case 'closed':
        return 'text-green-400'
      case 'half_open':
        return 'text-yellow-400'
      case 'open':
        return 'text-red-400'
      default:
        return 'text-gray-400'
    }
  }

  const getCircuitBreakerIcon = (status: string) => {
    switch (status) {
      case 'closed':
        return '🔒'
      case 'half_open':
        return '🔓'
      case 'open':
        return '⚠️'
      default:
        return '❓'
    }
  }

  const formatSuccessRate = (rate: number) => {
    return `${(rate * 100).toFixed(1)}%`
  }

  const getTrendIndicator = (current: number, previous: number | null) => {
    if (previous === null) return null

    const diff = current - previous
    if (Math.abs(diff) < 0.01) return '→'
    return diff > 0 ? '↗' : '↘'
  }

  const formatProcessingTime = (timeMs: number) => {
    if (timeMs < 1) return `${(timeMs * 1000).toFixed(0)}μs`
    if (timeMs < 1000) return `${timeMs.toFixed(0)}ms`
    return `${(timeMs / 1000).toFixed(1)}s`
  }

  return (
    <div class="border-b border-gray-800 bg-gray-900 p-3">
      <div class="mb-2 flex items-center justify-between">
        <h3 class="text-xs font-medium text-gray-300">Engine Metrics</h3>
        <Show when={!isConnected}>
          <div class="h-2 w-2 rounded-full bg-red-500" title="Disconnected" />
        </Show>
        <Show when={isConnected}>
          <div class="h-2 w-2 rounded-full bg-green-500" title="Connected" />
        </Show>
      </div>

      <Show
        when={isConnected && metrics}
        fallback={
          <div class="text-xs text-gray-500">
            <Show when={!isConnected} fallback={<span>Loading metrics...</span>}>
              <span class="text-red-400">Metrics unavailable</span>
            </Show>
          </div>
        }>
        <div class="space-y-3 text-xs">
          {/* Performance Metrics */}
          <div class="space-y-1">
            <div class="text-xs font-medium text-gray-400">Performance</div>

            <div class="flex justify-between">
              <span class="text-gray-400">Correlations/min:</span>
              <div class="flex items-center gap-1">
                <span class="font-mono text-blue-400">{metrics!.correlations_per_minute.toFixed(1)}</span>
                <Show when={previousMetrics()?.correlations_per_minute}>
                  <span class="text-gray-500">
                    {getTrendIndicator(metrics!.correlations_per_minute, previousMetrics()!.correlations_per_minute)}
                  </span>
                </Show>
              </div>
            </div>

            <div class="flex justify-between">
              <span class="text-gray-400">Avg Processing:</span>
              <span class="font-mono text-gray-300">{formatProcessingTime(metrics!.avg_processing_time)}</span>
            </div>

            <div class="flex justify-between">
              <span class="text-gray-400">Total Processed:</span>
              <span class="font-mono text-gray-300">{metrics!.correlation_count.toLocaleString()}</span>
            </div>
          </div>

          {/* System Health */}
          <div class="border-t border-gray-800 pt-2">
            <div class="mb-1 text-xs font-medium text-gray-400">System Health</div>

            <div class="flex justify-between">
              <span class="text-gray-400">Buffer Health:</span>
              <div class={`flex items-center gap-1 ${getHealthColor(metrics!.buffer_health_score)}`}>
                {getHealthIcon(metrics!.buffer_health_score)}
                <span class="font-mono">{(metrics!.buffer_health_score * 100).toFixed(0)}%</span>
              </div>
            </div>

            <div class="flex justify-between">
              <span class="text-gray-400">DB Success Rate:</span>
              <div class={`flex items-center gap-1 ${getHealthColor(metrics!.database_success_rate)}`}>
                <span class="font-mono">{formatSuccessRate(metrics!.database_success_rate)}</span>
                <Show when={previousMetrics()?.database_success_rate}>
                  <span class="text-gray-500">
                    {getTrendIndicator(metrics!.database_success_rate, previousMetrics()!.database_success_rate)}
                  </span>
                </Show>
              </div>
            </div>

            <div class="flex justify-between">
              <span class="text-gray-400">Circuit Breaker:</span>
              <div class={`flex items-center gap-1 ${getCircuitBreakerColor(metrics!.circuit_breaker_status)}`}>
                <span>{getCircuitBreakerIcon(metrics!.circuit_breaker_status)}</span>
                <span class="capitalize">{metrics!.circuit_breaker_status}</span>
              </div>
            </div>
          </div>

          {/* Buffer Status */}
          <Show when={engineStatus}>
            <div class="border-t border-gray-800 pt-2">
              <div class="mb-1 text-xs font-medium text-gray-400">Buffer Status</div>

              <div class="grid grid-cols-2 gap-2">
                <div class="text-center">
                  <div class="font-mono text-blue-400">{engineStatus!.transcription_count}</div>
                  <div class="text-gray-500">Transcripts</div>
                </div>
                <div class="text-center">
                  <div class="font-mono text-green-400">{engineStatus!.chat_count}</div>
                  <div class="text-gray-500">Chat Msgs</div>
                </div>
              </div>

              <div class="mt-1 flex justify-between">
                <span class="text-gray-400">Stream Active:</span>
                <div
                  class={`flex items-center gap-1 ${engineStatus!.stream_active ? 'text-green-400' : 'text-red-400'}`}>
                  <div class={`h-2 w-2 rounded-full ${engineStatus!.stream_active ? 'bg-green-500' : 'bg-red-500'}`} />
                  <span>{engineStatus!.stream_active ? 'Yes' : 'No'}</span>
                </div>
              </div>

              <Show when={engineStatus!.fingerprint_count > 0}>
                <div class="flex justify-between">
                  <span class="text-gray-400">Fingerprints:</span>
                  <span class="font-mono text-gray-300">{engineStatus!.fingerprint_count}</span>
                </div>
              </Show>
            </div>
          </Show>

          {/* Health Indicators */}
          <div class="border-t border-gray-800 pt-2">
            <div class="mb-1 text-xs font-medium text-gray-400">Status Indicators</div>

            <div class="grid grid-cols-2 gap-2 text-xs">
              <div
                class={`flex items-center gap-1 ${metrics!.buffer_health_score >= 0.8 ? 'text-green-400' : 'text-yellow-400'}`}>
                <div
                  class={`h-1 w-1 rounded-full ${metrics!.buffer_health_score >= 0.8 ? 'bg-green-500' : 'bg-yellow-500'}`}
                />
                <span>Buffer</span>
              </div>

              <div
                class={`flex items-center gap-1 ${metrics!.database_success_rate >= 0.95 ? 'text-green-400' : 'text-red-400'}`}>
                <div
                  class={`h-1 w-1 rounded-full ${metrics!.database_success_rate >= 0.95 ? 'bg-green-500' : 'bg-red-500'}`}
                />
                <span>Database</span>
              </div>

              <div
                class={`flex items-center gap-1 ${metrics!.avg_processing_time < 100 ? 'text-green-400' : 'text-yellow-400'}`}>
                <div
                  class={`h-1 w-1 rounded-full ${metrics!.avg_processing_time < 100 ? 'bg-green-500' : 'bg-yellow-500'}`}
                />
                <span>Speed</span>
              </div>

              <div
                class={`flex items-center gap-1 ${metrics!.correlations_per_minute > 0 ? 'text-green-400' : 'text-gray-400'}`}>
                <div
                  class={`h-1 w-1 rounded-full ${metrics!.correlations_per_minute > 0 ? 'bg-green-500' : 'bg-gray-500'}`}
                />
                <span>Activity</span>
              </div>
            </div>
          </div>
        </div>
      </Show>
    </div>
  )
}
