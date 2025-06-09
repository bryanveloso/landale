import { useCallback } from 'react'
import { trpc } from '@/lib/trpc'

/**
 * Hook for triggering one-time subscription actions in a WebSocket-only environment
 * Since tRPC WebSocket doesn't support mutations, we use subscriptions that complete after one emission
 */
export function useSubscriptionAction<TInput = void, TOutput = unknown>(path: string) {
  const execute = useCallback(
    async (input?: TInput): Promise<TOutput | undefined> => {
      return new Promise((resolve, reject) => {
        const pathParts = path.split('.')
        let current: any = trpc

        // Navigate to the subscription method
        for (const part of pathParts) {
          current = current[part]
          if (!current) {
            reject(new Error(`Invalid subscription path: ${path}`))
            return
          }
        }

        // Subscribe and take the first value
        const subscription = current.subscribe(input, {
          onData: (data: TOutput) => {
            resolve(data)
            subscription.unsubscribe()
          },
          onError: (error: unknown) => {
            reject(error)
            subscription.unsubscribe()
          }
        })
      })
    },
    [path]
  )

  return { execute }
}
