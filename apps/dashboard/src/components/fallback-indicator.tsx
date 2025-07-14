/**
 * Fallback Indicator Component
 *
 * Shows when the system is running in fallback mode due to service failures.
 * Provides visual feedback that some data may be incomplete or unavailable.
 */

import { Show } from 'solid-js'

interface FallbackContent {
  fallback_mode?: boolean
  fallback?: boolean
  message?: string
}

interface FallbackIndicatorProps {
  content?: FallbackContent | null
  type?: 'content' | 'system' | 'connection'
  message?: string
}

export function FallbackIndicator(props: FallbackIndicatorProps) {
  const isFallbackMode = () => {
    if (props.message) return true
    if (!props.content) return false

    // Check various fallback indicators
    return (
      props.content.fallback_mode ||
      props.content.fallback ||
      props.content.message?.includes('temporarily unavailable') ||
      props.content.message?.includes('fallback')
    )
  }

  const getFallbackMessage = () => {
    if (props.message) return props.message
    if (props.content?.message) return props.content.message

    switch (props.type) {
      case 'content':
        return 'Some content is temporarily unavailable'
      case 'system':
        return 'System is running in fallback mode'
      case 'connection':
        return 'Connection issues detected'
      default:
        return 'Some features may be limited'
    }
  }

  return (
    <Show when={isFallbackMode()}>
      <div class="fallback-indicator">
        <div class="fallback-icon">⚠️</div>
        <div class="fallback-message">{getFallbackMessage()}</div>
      </div>
    </Show>
  )
}
