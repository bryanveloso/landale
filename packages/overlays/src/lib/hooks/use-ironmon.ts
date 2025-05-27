import { useQueryClient } from '@tanstack/react-query'
import { useSubscription } from '@trpc/tanstack-react-query'
import { useTRPC } from '@/lib/trpc'
import type { IronmonEvent } from '@landale/server/events/ironmon/types'

type IronmonMessage = IronmonEvent[keyof IronmonEvent]

export function useIronmonSubscription() {
  const queryClient = useQueryClient()
  const trpc = useTRPC()

  // Subscribe to all IronMON messages
  useSubscription(
    trpc.ironmon.onMessage.subscriptionOptions(undefined, {
      onData: (data) => {
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
  )
}

export function useIronmonCheckpoint() {
  const queryClient = useQueryClient()
  const trpc = useTRPC()

  useSubscription(
    trpc.ironmon.onCheckpoint.subscriptionOptions(undefined, {
      onData: (data) => {
        queryClient.setQueryData(['ironmon', 'checkpoint'], data.metadata)
      }
    })
  )

  return queryClient.getQueryData(['ironmon', 'checkpoint'])
}

export function useIronmonSeed() {
  const queryClient = useQueryClient()
  const trpc = useTRPC()

  useSubscription(
    trpc.ironmon.onSeed.subscriptionOptions(undefined, {
      onData: (data) => {
        queryClient.setQueryData(['ironmon', 'seed'], data.metadata)
      }
    })
  )

  return queryClient.getQueryData(['ironmon', 'seed'])
}
