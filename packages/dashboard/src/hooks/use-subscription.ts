import { useEffect, useState, useCallback } from 'react'
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

  const updateConnectionState = useCallback(
    (newState: ConnectionState) => {
      setConnectionState(newState)
      onConnectionStateChange?.(newState)
    },
    [onConnectionStateChange]
  )

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
        onData?.(receivedData)
      },
      onError: (err: Error) => {
        setError(err)
        updateConnectionState({ state: 'error', error: err.message })
        onError?.(err)
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
  }, [path, input, enabled, onData, onError, updateConnectionState])

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
