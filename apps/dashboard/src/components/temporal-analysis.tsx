import { createSignal, createEffect, For, Show } from 'solid-js'
import { Chart, registerables } from 'chart.js'
import { usePhoenixService } from '~/hooks/use-phoenix-service'

Chart.register(...registerables)

interface DelayEstimate {
  estimated_delay_ms: number
  confidence: number
  last_estimation: string
}

interface TemporalMetrics {
  correlation_count: number
  temporal_patterns: Record<string, number>
  delay_estimation: DelayEstimate
  analyzer_health: {
    signal_health: {
      transcription_buckets: number
      chat_buckets: number
      signal_age_minutes: number
    }
    estimation_metrics: {
      total_estimations: number
      successful_estimations: number
      success_rate: number
      last_correlation_peak: number
    }
  }
  buffer_sizes: {
    transcription: number
    chat: number
  }
}

interface TemporalCorrelation {
  id: string
  pattern: string
  temporal_pattern: string
  confidence: number
  transcription: string
  chat_user: string
  chat_message: string
  time_offset_ms: number
  timing_deviation_ms: number
  delay_confidence: number
  timestamp: number
}

export function TemporalAnalysis() {
  const { socket, isConnected } = usePhoenixService()
  const [metrics, setMetrics] = createSignal<TemporalMetrics | null>(null)
  const [recentCorrelations, setRecentCorrelations] = createSignal<TemporalCorrelation[]>([])
  const [isLoading, setIsLoading] = createSignal(true)

  let delayChartRef: HTMLCanvasElement | undefined
  let delayChart: Chart | null = null

  createEffect(() => {
    if (!socket() || !isConnected()) return

    const channel = socket()!.channel('correlation:temporal', {})

    channel
      .join()
      .receive('ok', () => {
        console.log('Connected to temporal correlation channel')
        // Request initial metrics
        channel.push('get_temporal_metrics', {})
      })
      .receive('error', (resp) => {
        console.error('Unable to join temporal channel', resp)
      })

    // Handle temporal metrics updates
    channel.on('temporal_metrics', (data: TemporalMetrics) => {
      setMetrics(data)
      setIsLoading(false)
      updateDelayChart(data.delay_estimation)
    })

    // Handle new temporal correlations
    channel.on('temporal_correlation', (correlation: TemporalCorrelation) => {
      setRecentCorrelations((prev) => [correlation, ...prev.slice(0, 19)]) // Keep last 20
    })

    return () => {
      channel.leave()
    }
  })

  const updateDelayChart = (delayData: DelayEstimate) => {
    if (!delayChartRef) return

    if (!delayChart) {
      const ctx = delayChartRef.getContext('2d')!
      delayChart = new Chart(ctx, {
        type: 'line',
        data: {
          labels: [],
          datasets: [
            {
              label: 'Stream Delay (ms)',
              data: [],
              borderColor: 'rgb(59, 130, 246)',
              backgroundColor: 'rgba(59, 130, 246, 0.1)',
              tension: 0.1
            }
          ]
        },
        options: {
          responsive: true,
          scales: {
            y: {
              beginAtZero: false,
              title: {
                display: true,
                text: 'Delay (milliseconds)'
              }
            },
            x: {
              title: {
                display: true,
                text: 'Time'
              }
            }
          },
          plugins: {
            title: {
              display: true,
              text: 'Stream Delay Detection Over Time'
            }
          }
        }
      })
    }

    // Add new data point
    const now = new Date().toLocaleTimeString()
    delayChart.data.labels!.push(now)
    delayChart.data.datasets[0].data.push(delayData.estimated_delay_ms)

    // Keep only last 20 points
    if (delayChart.data.labels!.length > 20) {
      delayChart.data.labels!.shift()
      delayChart.data.datasets[0].data.shift()
    }

    delayChart.update('none')
  }

  const formatDelayConfidence = (confidence: number) => {
    if (confidence >= 0.8) return { text: 'High', class: 'text-green-400' }
    if (confidence >= 0.6) return { text: 'Medium', class: 'text-yellow-400' }
    if (confidence >= 0.4) return { text: 'Low', class: 'text-orange-400' }
    return { text: 'Very Low', class: 'text-red-400' }
  }

  const formatTemporalPattern = (pattern: string) => {
    const patterns: Record<string, { label: string; color: string }> = {
      immediate_reaction: { label: 'Immediate', color: 'bg-green-500' },
      quick_response: { label: 'Quick', color: 'bg-blue-500' },
      delayed_reaction: { label: 'Delayed', color: 'bg-yellow-500' },
      discussion_spawn: { label: 'Discussion', color: 'bg-purple-500' },
      outlier: { label: 'Outlier', color: 'bg-gray-500' }
    }
    return patterns[pattern] || { label: pattern, color: 'bg-gray-500' }
  }

  return (
    <div class="space-y-6">
      {/* Header */}
      <div class="flex items-center justify-between">
        <h2 class="text-2xl font-bold text-white">Temporal Analysis</h2>
        <div class="flex items-center space-x-2">
          <div class={`h-3 w-3 rounded-full ${isConnected() ? 'bg-green-400' : 'bg-red-400'}`} />
          <span class="text-sm text-gray-400">{isConnected() ? 'Connected' : 'Disconnected'}</span>
        </div>
      </div>

      <Show when={isLoading()}>
        <div class="flex items-center justify-center py-12">
          <div class="h-8 w-8 animate-spin rounded-full border-b-2 border-blue-400" />
          <span class="ml-3 text-gray-400">Loading temporal analysis...</span>
        </div>
      </Show>

      <Show when={!isLoading() && metrics()}>
        {(currentMetrics) => (
          <>
            {/* Delay Estimation Overview */}
            <div class="grid grid-cols-1 gap-6 md:grid-cols-3">
              <div class="rounded-lg bg-gray-800 p-6">
                <h3 class="mb-4 text-lg font-semibold text-white">Stream Delay</h3>
                <div class="mb-2 text-3xl font-bold text-blue-400">
                  {(currentMetrics().delay_estimation.estimated_delay_ms / 1000).toFixed(1)}s
                </div>
                <div class="text-sm text-gray-400">
                  Confidence:{' '}
                  <span class={formatDelayConfidence(currentMetrics().delay_estimation.confidence).class}>
                    {formatDelayConfidence(currentMetrics().delay_estimation.confidence).text}
                  </span>
                </div>
              </div>

              <div class="rounded-lg bg-gray-800 p-6">
                <h3 class="mb-4 text-lg font-semibold text-white">Signal Health</h3>
                <div class="space-y-2">
                  <div class="flex justify-between">
                    <span class="text-gray-400">Transcription:</span>
                    <span class="text-white">
                      {currentMetrics().analyzer_health.signal_health.transcription_buckets} buckets
                    </span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-gray-400">Chat:</span>
                    <span class="text-white">
                      {currentMetrics().analyzer_health.signal_health.chat_buckets} buckets
                    </span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-gray-400">Age:</span>
                    <span class="text-white">
                      {currentMetrics().analyzer_health.signal_health.signal_age_minutes.toFixed(1)}m
                    </span>
                  </div>
                </div>
              </div>

              <div class="rounded-lg bg-gray-800 p-6">
                <h3 class="mb-4 text-lg font-semibold text-white">Estimation Quality</h3>
                <div class="space-y-2">
                  <div class="flex justify-between">
                    <span class="text-gray-400">Success Rate:</span>
                    <span class="text-white">
                      {(currentMetrics().analyzer_health.estimation_metrics.success_rate * 100).toFixed(1)}%
                    </span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-gray-400">Last Peak:</span>
                    <span class="text-white">
                      {currentMetrics().analyzer_health.estimation_metrics.last_correlation_peak.toFixed(3)}
                    </span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-gray-400">Total Est:</span>
                    <span class="text-white">
                      {currentMetrics().analyzer_health.estimation_metrics.total_estimations}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Delay Chart */}
            <div class="rounded-lg bg-gray-800 p-6">
              <h3 class="mb-4 text-lg font-semibold text-white">Delay Detection History</h3>
              <canvas ref={delayChartRef} class="h-64 w-full" />
            </div>

            {/* Temporal Pattern Distribution */}
            <Show when={Object.keys(currentMetrics().temporal_patterns).length > 0}>
              <div class="rounded-lg bg-gray-800 p-6">
                <h3 class="mb-4 text-lg font-semibold text-white">Temporal Pattern Distribution</h3>
                <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
                  <For each={Object.entries(currentMetrics().temporal_patterns)}>
                    {([pattern, count]) => {
                      const patternInfo = formatTemporalPattern(pattern)
                      return (
                        <div class="text-center">
                          <div class={`h-4 w-4 ${patternInfo.color} mx-auto mb-2 rounded`} />
                          <div class="font-semibold text-white">{count}</div>
                          <div class="text-sm text-gray-400">{patternInfo.label}</div>
                        </div>
                      )
                    }}
                  </For>
                </div>
              </div>
            </Show>

            {/* Recent Temporal Correlations */}
            <div class="rounded-lg bg-gray-800 p-6">
              <h3 class="mb-4 text-lg font-semibold text-white">Recent Temporal Correlations</h3>
              <div class="max-h-96 space-y-3 overflow-y-auto">
                <For each={recentCorrelations()}>
                  {(correlation) => {
                    const patternInfo = formatTemporalPattern(correlation.temporal_pattern)
                    return (
                      <div class="rounded border-l-4 border-blue-400 bg-gray-700 p-4">
                        <div class="mb-2 flex items-center justify-between">
                          <div class="flex items-center space-x-2">
                            <span class={`rounded px-2 py-1 text-xs ${patternInfo.color} text-white`}>
                              {patternInfo.label}
                            </span>
                            <span class="text-sm text-gray-400">{correlation.pattern}</span>
                          </div>
                          <div class="text-sm text-gray-400">
                            {(correlation.confidence * 100).toFixed(0)}% confidence
                          </div>
                        </div>
                        <div class="mb-1 text-sm text-gray-300">
                          <strong>Transcription:</strong> {correlation.transcription}
                        </div>
                        <div class="mb-2 text-sm text-gray-300">
                          <strong>{correlation.chat_user}:</strong> {correlation.chat_message}
                        </div>
                        <div class="flex space-x-4 text-xs text-gray-400">
                          <span>Offset: {(correlation.time_offset_ms / 1000).toFixed(1)}s</span>
                          <span>Deviation: {(correlation.timing_deviation_ms / 1000).toFixed(1)}s</span>
                          <span>Delay Conf: {(correlation.delay_confidence * 100).toFixed(0)}%</span>
                        </div>
                      </div>
                    )
                  }}
                </For>
                <Show when={recentCorrelations().length === 0}>
                  <div class="py-8 text-center text-gray-400">No temporal correlations detected yet</div>
                </Show>
              </div>
            </div>
          </>
        )}
      </Show>
    </div>
  )
}
