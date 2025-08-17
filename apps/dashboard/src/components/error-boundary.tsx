/**
 * Connection State Monitor for WebSocket failures
 *
 * Monitors connection health and provides fallback UI when connections fail.
 * Note: This is not a traditional error boundary, but a connection state monitor.
 */

import { createSignal, createEffect } from 'solid-js'
import type { Component, JSX } from 'solid-js'
import { usePhoenixService } from '@/services/phoenix-service'

interface ConnectionMonitorProps {
  children: JSX.Element
  fallback?: Component<{ error: Error; retry: () => void }>
}

interface ErrorState {
  hasError: boolean
  error: Error | null
  retryCount: number
}

export const ConnectionMonitor: Component<ConnectionMonitorProps> = (props) => {
  const { isConnected, reconnect } = usePhoenixService()
  const [errorState, setErrorState] = createSignal<ErrorState>({
    hasError: false,
    error: null,
    retryCount: 0
  })
  const [reconnectAttempts, setReconnectAttempts] = createSignal(0)

  // Monitor connection state for critical errors
  createEffect(() => {
    const connected = isConnected()

    // Show error state after multiple failed reconnection attempts
    if (!connected && reconnectAttempts() >= 3) {
      setErrorState((prev) => ({
        hasError: true,
        error: new Error('WebSocket connection failed'),
        retryCount: prev.retryCount
      }))
    } else if (connected && errorState().hasError) {
      // Reset error state on successful connection
      setErrorState({
        hasError: false,
        error: null,
        retryCount: 0
      })
      setReconnectAttempts(0)
    } else if (!connected) {
      setReconnectAttempts((prev) => prev + 1)
    }
  })

  const handleRetry = () => {
    setErrorState((prev) => ({
      hasError: false,
      error: null,
      retryCount: prev.retryCount + 1
    }))
    setReconnectAttempts(0)

    // Force reconnection attempt
    reconnect()
  }

  const FallbackComponent = props.fallback || DefaultErrorFallback

  return (
    <>
      {errorState().hasError ? <FallbackComponent error={errorState().error!} retry={handleRetry} /> : props.children}
    </>
  )
}

const DefaultErrorFallback: Component<{ error: Error; retry: () => void }> = (props) => {
  return (
    <div class="bg-ink flex h-full flex-col items-center justify-center rounded border border-red-200/10 p-6">
      <div class="text-center">
        <h2 class="mb-2 text-lg font-semibold text-red-800">Connection Lost</h2>
        <p class="mb-4 text-red-600">{props.error.message}</p>
        <button
          onClick={props.retry}
          class="rounded bg-red-600 px-4 py-2 text-white transition-colors hover:bg-red-700">
          Retry Connection
        </button>
      </div>
    </div>
  )
}
