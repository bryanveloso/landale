import { useEffect, useState, useCallback, useRef } from 'react'
import { trpcClient } from '@/lib/trpc-client'
import type { ConnectionState } from '@/types'

interface SubscriptionOptions<T> {
  onData?: (data: T) => void
  onError?: (error: Error) => void
  onConnectionStateChange?: (state: ConnectionState) => void
  enabled?: boolean
}

export function useSubscription<T>(path: string, input: unknown = undefined, options: SubscriptionOptions<T> = {}) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [connectionState, setConnectionState] = useState<ConnectionState>({
    state: 'idle'
  })

  const { onData, onError, onConnectionStateChange, enabled = true } = options

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

  // Use ref for onConnectionStateChange to avoid dependency issues
  const onConnectionStateChangeRef = useRef(onConnectionStateChange)
  useEffect(() => {
    onConnectionStateChangeRef.current = onConnectionStateChange
  }, [onConnectionStateChange])

  const updateConnectionState = useCallback((newState: ConnectionState) => {
    setConnectionState(newState)
    onConnectionStateChangeRef.current?.(newState)
  }, [])

  // Stringify input for stable comparison
  const inputKey = JSON.stringify(input)

  useEffect(() => {
    if (!enabled) {
      updateConnectionState({ state: 'idle' })
      return
    }

    updateConnectionState({ state: 'connecting' })

    // Get the procedure from the tRPC client using the path
    const pathParts = path.split('.')
    let procedure: any = trpcClient

    for (const part of pathParts) {
      procedure = procedure[part]
    }

    const subscription = procedure.subscribe(input, {
      onData: (receivedData: T) => {
        setData(receivedData)
        setError(null)
        updateConnectionState({ state: 'connected' })
        onDataRef.current?.(receivedData)
      },
      onError: (err: Error) => {
        setError(err)
        updateConnectionState({ state: 'error', error: err.message })
        onErrorRef.current?.(err)
      },
      onStarted: () => {
        updateConnectionState({ state: 'connected' })
      },
      onStopped: () => {
        updateConnectionState({ state: 'disconnected' })
      }
    })

    return () => {
      subscription.unsubscribe()
      updateConnectionState({ state: 'idle' })
    }
  }, [path, inputKey, enabled, updateConnectionState])

  const reset = useCallback(() => {
    setData(null)
    setError(null)
    setConnectionState({ state: 'idle' })
  }, [])

  return {
    data,
    error,
    connectionState,
    isConnected: connectionState.state === 'connected',
    isConnecting: connectionState.state === 'connecting',
    isError: connectionState.state === 'error',
    reset
  }
}
