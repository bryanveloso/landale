import { useEffect, useState, useCallback, useRef } from 'react'
import { trpcClient } from '@/lib/trpc-client'
import type { ConnectionState } from '@/types'

interface SubscriptionOptions<T> {
  onData?: (data: T) => void
  onError?: (error: Error) => void
  onConnectionStateChange?: (state: ConnectionState) => void
  enabled?: boolean
  maxRetries?: number
  initialRetryDelay?: number
  maxRetryDelay?: number
  retryMultiplier?: number
}

export function useSubscription<T>(path: string, input: unknown = undefined, options: SubscriptionOptions<T> = {}) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [connectionState, setConnectionState] = useState<ConnectionState>({
    state: 'idle'
  })

  const {
    onData,
    onError,
    onConnectionStateChange,
    enabled = true,
    maxRetries = 5,
    initialRetryDelay = 1000,
    maxRetryDelay = 30000,
    retryMultiplier = 2
  } = options

  const retryCountRef = useRef(0)
  const retryDelayRef = useRef(initialRetryDelay)
  const retryTimeoutRef = useRef<number | null>(null)
  const subscriptionRef = useRef<{ unsubscribe: () => void } | null>(null)
  const enabledRef = useRef(enabled)

  // Use refs to store callbacks to avoid dependency issues
  const onDataRef = useRef(onData)
  const onErrorRef = useRef(onError)

  // Update refs when callbacks change
  useEffect(() => {
    onDataRef.current = onData
  }, [onData])

  useEffect(() => {
    onErrorRef.current = onError
  }, [onError])

  useEffect(() => {
    enabledRef.current = enabled
  }, [enabled])

  // Use ref for onConnectionStateChange to avoid dependency issues
  const onConnectionStateChangeRef = useRef(onConnectionStateChange)
  useEffect(() => {
    onConnectionStateChangeRef.current = onConnectionStateChange
  }, [onConnectionStateChange])

  const updateConnectionState = useCallback((newState: ConnectionState) => {
    setConnectionState(newState)
    onConnectionStateChangeRef.current?.(newState)
  }, [])

  // Track input changes
  const inputKey = JSON.stringify(input)

  const clearRetryTimeout = useCallback(() => {
    if (retryTimeoutRef.current) {
      window.clearTimeout(retryTimeoutRef.current)
      retryTimeoutRef.current = null
    }
  }, [])

  const resetRetryState = useCallback(() => {
    retryCountRef.current = 0
    retryDelayRef.current = initialRetryDelay
    clearRetryTimeout()
  }, [initialRetryDelay, clearRetryTimeout])

  const scheduleRetry = useCallback(() => {
    if (retryCountRef.current >= maxRetries) {
      updateConnectionState({
        state: 'error',
        error: `Failed to connect after ${String(maxRetries)} attempts`
      })
      return
    }

    const delay = Math.min(retryDelayRef.current, maxRetryDelay)

    updateConnectionState({
      state: 'reconnecting',
      retryCount: retryCountRef.current + 1,
      nextRetryIn: delay
    })

    retryTimeoutRef.current = window.setTimeout(() => {
      retryCountRef.current++
      retryDelayRef.current = Math.min(retryDelayRef.current * retryMultiplier, maxRetryDelay)
      // Trigger reconnection
      if (subscriptionRef.current) {
        subscriptionRef.current.unsubscribe()
        subscriptionRef.current = null
      }
    }, delay)
  }, [maxRetries, maxRetryDelay, retryMultiplier, updateConnectionState])

  useEffect(() => {
    if (!enabled) {
      updateConnectionState({ state: 'idle' })
      clearRetryTimeout()
      if (subscriptionRef.current) {
        subscriptionRef.current.unsubscribe()
        subscriptionRef.current = null
      }
      return
    }

    // Clean up existing subscription before creating a new one
    if (subscriptionRef.current) {
      subscriptionRef.current.unsubscribe()
      subscriptionRef.current = null
    }


    updateConnectionState({ state: 'connecting' })

    // Get the procedure from the tRPC client using the path
    // We use Function here because tRPC procedures are callable objects
    const getProcedure = (obj: unknown, path: string[]): unknown => {
      let current = obj
      for (const part of path) {
        current = (current as Record<string, unknown>)[part]
      }
      return current
    }

    const pathParts = path.split('.')
    const procedure = getProcedure(trpcClient, pathParts)

    try {
      // Type assertion is safe here because we know the path leads to a subscription procedure
      const subscribe = procedure as {
        subscribe: (
          input: unknown,
          opts: {
            onData: (data: T) => void
            onError: (err: Error) => void
            onStarted: () => void
            onStopped: () => void
          }
        ) => { unsubscribe: () => void }
      }

      const subscription = subscribe.subscribe(input, {
        onData: (receivedData: T) => {
          setData(receivedData)
          setError(null)
          updateConnectionState({ state: 'connected' })
          resetRetryState()
          onDataRef.current?.(receivedData)
        },
        onError: (err: Error) => {
          setError(err)
          onErrorRef.current?.(err)
          scheduleRetry()
        },
        onStarted: () => {
          updateConnectionState({ state: 'connected' })
          resetRetryState()
        },
        onStopped: () => {
          if (enabledRef.current) {
            scheduleRetry()
          } else {
            updateConnectionState({ state: 'disconnected' })
          }
        }
      })

      subscriptionRef.current = subscription
    } catch (err) {
      const error = err instanceof Error ? err : new Error('Failed to create subscription')
      setError(error)
      updateConnectionState({ state: 'error', error: error.message })
      onErrorRef.current?.(error)
      scheduleRetry()
    }

    return () => {
      clearRetryTimeout()
      if (subscriptionRef.current) {
        subscriptionRef.current.unsubscribe()
        subscriptionRef.current = null
      }
      updateConnectionState({ state: 'idle' })
    }
  }, [path, inputKey, enabled, updateConnectionState, resetRetryState, scheduleRetry, clearRetryTimeout])

  const reset = useCallback(() => {
    setData(null)
    setError(null)
    setConnectionState({ state: 'idle' })
    resetRetryState()
  }, [resetRetryState])

  return {
    data,
    error,
    connectionState,
    isConnected: connectionState.state === 'connected',
    isConnecting: connectionState.state === 'connecting',
    isReconnecting: connectionState.state === 'reconnecting',
    isError: connectionState.state === 'error',
    reset
  }
}
