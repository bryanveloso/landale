import { createSignal, createEffect, onCleanup } from 'solid-js'
import { usePhoenixService } from '@/services/phoenix-service'
import { createLogger } from '@landale/logger/browser'
import type { Channel } from 'phoenix'

const logger = createLogger({
  service: 'dashboard'
})

// Correlation data types
export interface Correlation {
  id: string
  transcription_id: string
  transcription_text: string
  chat_message_id: string
  chat_user: string
  chat_text: string
  pattern_type: 'direct_quote' | 'keyword_echo' | 'emote_reaction' | 'question_response' | 'temporal_only'
  confidence: number
  time_offset_ms: number
  detected_keywords: string[]
  session_id?: string
  created_at: string
}

export interface CorrelationMetrics {
  correlation_count: number
  correlations_per_minute: number
  buffer_health_score: number
  database_success_rate: number
  avg_processing_time: number
  circuit_breaker_status: 'open' | 'closed' | 'half_open'
}

export interface EngineStatus {
  transcription_count: number
  chat_count: number
  correlation_count: number
  stream_active: boolean
  fingerprint_count: number
}

export interface PatternDistribution {
  [pattern: string]: number
}

export interface CorrelationChannelState {
  correlations: Correlation[]
  metrics: CorrelationMetrics | null
  engineStatus: EngineStatus | null
  patternDistribution: PatternDistribution
  isConnected: boolean
}

const DEFAULT_STATE: CorrelationChannelState = {
  correlations: [],
  metrics: null,
  engineStatus: null,
  patternDistribution: {},
  isConnected: false
}

export function useCorrelationChannel() {
  const { socket, isConnected } = usePhoenixService()
  const [channel, setChannel] = createSignal<Channel | null>(null)
  const [state, setState] = createSignal<CorrelationChannelState>(DEFAULT_STATE)

  // Setup channel connection
  createEffect(() => {
    const phoenixSocket = socket()
    const connected = isConnected()

    if (phoenixSocket && connected && !channel()) {
      const correlationChannel = phoenixSocket.channel('correlation:dashboard', {})

      correlationChannel
        .join()
        .receive('ok', () => {
          logger.info('Joined correlation channel')
          setChannel(correlationChannel)
          setState((prev) => ({ ...prev, isConnected: true }))

          // Request initial data
          requestMetrics()
          requestEngineStatus()
          requestRecentCorrelations()
          requestPatternDistribution()
        })
        .receive('error', (resp) => {
          logger.error('Failed to join correlation channel', { error: resp })
          setState((prev) => ({ ...prev, isConnected: false }))
        })

      // Set up event handlers
      correlationChannel.on('new_correlation', (correlation: Correlation) => {
        logger.debug('New correlation received', {
          metadata: { correlation }
        })
        setState((prev) => ({
          ...prev,
          correlations: [correlation, ...prev.correlations.slice(0, 49)] // Keep last 50
        }))
      })

      correlationChannel.on('correlation_metrics', (payload: { data: CorrelationMetrics; timestamp: number }) => {
        logger.debug('Correlation metrics received', {
          metadata: { metrics: payload.data }
        })
        setState((prev) => ({ ...prev, metrics: payload.data }))
      })

      setChannel(correlationChannel)
    } else if (!connected && channel()) {
      // Disconnect
      channel()?.leave()
      setChannel(null)
      setState((prev) => ({ ...prev, isConnected: false }))
    }
  })

  // Cleanup on unmount
  onCleanup(() => {
    const currentChannel = channel()
    if (currentChannel) {
      currentChannel.leave()
      setChannel(null)
    }
  })

  const requestMetrics = () => {
    const currentChannel = channel()
    if (!currentChannel) return

    currentChannel
      .push('get_metrics', {})
      .receive('ok', (resp) => {
        if (resp.data) {
          setState((prev) => ({ ...prev, metrics: resp.data }))
        }
      })
      .receive('error', (resp) => {
        logger.error('Failed to get metrics', { error: resp })
      })
  }

  const requestEngineStatus = () => {
    const currentChannel = channel()
    if (!currentChannel) return

    currentChannel
      .push('get_engine_status', {})
      .receive('ok', (resp) => {
        if (resp.data) {
          setState((prev) => ({ ...prev, engineStatus: resp.data }))
        }
      })
      .receive('error', (resp) => {
        logger.error('Failed to get engine status', { error: resp })
      })
  }

  const requestRecentCorrelations = (limit = 20) => {
    const currentChannel = channel()
    if (!currentChannel) return

    currentChannel
      .push('get_correlations', { limit })
      .receive('ok', (resp) => {
        if (resp.data?.correlations) {
          setState((prev) => ({ ...prev, correlations: resp.data.correlations }))
        }
      })
      .receive('error', (resp) => {
        logger.error('Failed to get correlations', { error: resp })
      })
  }

  const requestPatternDistribution = () => {
    const currentChannel = channel()
    if (!currentChannel) return

    currentChannel
      .push('get_pattern_distribution', {})
      .receive('ok', (resp) => {
        if (resp.data?.patterns) {
          setState((prev) => ({ ...prev, patternDistribution: resp.data.patterns }))
        }
      })
      .receive('error', (resp) => {
        logger.error('Failed to get pattern distribution', { error: resp })
      })
  }

  return {
    ...state(),
    requestMetrics,
    requestEngineStatus,
    requestRecentCorrelations,
    requestPatternDistribution
  }
}
