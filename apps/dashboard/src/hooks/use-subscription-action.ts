import { useCallback } from 'react'
import { trpc } from '@/lib/trpc'

/**
 * Hook for triggering one-time subscription actions in a WebSocket-only environment
 * Since tRPC WebSocket doesn't support mutations, we use subscriptions that complete after one emission
 */
export function useSubscriptionAction<TOutput = unknown>(path: string) {
  const execute = useCallback(
    async (input?: unknown): Promise<TOutput | undefined> => {
      return new Promise((resolve, reject) => {
        const pathParts = path.split('.')
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        let current: any = trpc

        // Navigate to the subscription method
        for (const part of pathParts) {
          // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-member-access
          current = current[part]
          if (!current) {
            reject(new Error(`Invalid subscription path: ${path}`))
            return
          }
        }

        // Subscribe and take the first value
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-unsafe-call
        const subscription = current.subscribe(input, {
          onData: (data: TOutput) => {
            resolve(data)
            // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-unsafe-call
            subscription.unsubscribe()
          },
          onError: (error: unknown) => {
            reject(error instanceof Error ? error : new Error(String(error)))
            // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access, @typescript-eslint/no-unsafe-call
            subscription.unsubscribe()
          }
        })
      })
    },
    [path]
  )

  return { execute }
}
