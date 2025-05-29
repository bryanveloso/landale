import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { trpcClient } from '@/lib/trpc'
import type { IronmonEvent } from '@landale/server'

type IronmonMessage = IronmonEvent[keyof IronmonEvent]

export function useIronmonSubscription() {
  const queryClient = useQueryClient()

  useEffect(() => {
    const subscription = trpcClient.ironmon.onMessage.subscribe(undefined, {
      onData: (data: unknown) => {
        const message = data as IronmonMessage
        // Handle different message types
        switch (message.type) {
          case 'checkpoint':
            queryClient.setQueryData(['ironmon', 'checkpoint'], message.metadata)
            break
          case 'seed':
            queryClient.setQueryData(['ironmon', 'seed'], message.metadata)
            break
          case 'init':
            queryClient.setQueryData(['ironmon', 'init'], message.metadata)
            break
          case 'location':
            queryClient.setQueryData(['ironmon', 'location'], message.metadata)
            break
        }

        // Log for debugging
        console.log(`IronMON ${message.type}:`, message.metadata)
        console.log('Query cache updated with:', queryClient.getQueryData(['ironmon', message.type]))
      }
    })

    return () => subscription.unsubscribe()
  }, [queryClient])
}

export function useIronmonCheckpoint() {
  const queryClient = useQueryClient()

  useEffect(() => {
    const subscription = trpcClient.ironmon.onCheckpoint.subscribe(undefined, {
      onData: (data: unknown) => {
        queryClient.setQueryData(['ironmon', 'checkpoint'], (data as { metadata: unknown }).metadata)
      }
    })

    return () => subscription.unsubscribe()
  }, [queryClient])

  return queryClient.getQueryData(['ironmon', 'checkpoint'])
}

export function useIronmonSeed() {
  const queryClient = useQueryClient()

  useEffect(() => {
    const subscription = trpcClient.ironmon.onSeed.subscribe(undefined, {
      onData: (data: unknown) => {
        queryClient.setQueryData(['ironmon', 'seed'], (data as { metadata: unknown }).metadata)
      }
    })

    return () => subscription.unsubscribe()
  }, [queryClient])

  return queryClient.getQueryData(['ironmon', 'seed'])
}
