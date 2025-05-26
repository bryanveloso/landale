import { useQueryClient } from '@tanstack/react-query'
import { useSubscription } from '@trpc/tanstack-react-query'
import { useTRPC } from '@/lib/trpc'

export function useIronmonSubscription() {
  const queryClient = useQueryClient()
  const trpc = useTRPC()

  // Subscribe to all IronMON messages
  useSubscription(
    trpc.ironmon.onMessage.subscriptionOptions(undefined, {
      onData: (data) => {
        // Update query cache based on message type
        queryClient.setQueryData(['ironmon', data.type], data.metadata)

        // Log for debugging
        console.log(`IronMON ${data.type}:`, data.metadata)
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
