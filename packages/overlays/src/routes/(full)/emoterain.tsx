import { useTRPC } from '@/lib/trpc'
import { createFileRoute } from '@tanstack/react-router'
import { useSubscription } from '@trpc/tanstack-react-query'
import { EmoteRain } from '@/components/emoterain/emote-rain'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/(full)/emoterain')({
  component: RouteComponent
})

function RouteComponent() {
  const trpc = useTRPC()

  useSubscription(
    trpc.twitch.onMessage.subscriptionOptions(undefined, {
      onData: (data) => {
        console.log('onMessage', data.messageId)

        // Process message parts to find emotes
        if (data.messageParts) {
          data.messageParts.forEach((part) => {
            if (part.type === 'emote' && part.emote) {
              console.log('Emote found:', part.emote.id)
              console.log('Full emote object:', part.emote)
              console.log('Window.queueEmote exists?', !!(window as any).queueEmote)
              // Queue the emote
              if ((window as any).queueEmote) {
                console.log('Queueing emote:', part.emote.id)
                ;(window as any).queueEmote(part.emote.id)
              }
            }
          })
        }
      }
    })
  )

  return (
    <ErrorBoundary>
      <EmoteRain />
    </ErrorBoundary>
  )
}
