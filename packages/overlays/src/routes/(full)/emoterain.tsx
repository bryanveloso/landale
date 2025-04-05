import { useTRPC } from '@/lib/trpc'
import { createFileRoute } from '@tanstack/react-router'
import { useSubscription } from '@trpc/tanstack-react-query'

export const Route = createFileRoute('/(full)/emoterain')({
  component: RouteComponent
})

function RouteComponent() {
  const trpc = useTRPC()
  useSubscription(trpc.twitch.onMessage.subscriptionOptions(undefined, {}))

  return <div>Hello "/(full)/emoterain"!</div>
}
