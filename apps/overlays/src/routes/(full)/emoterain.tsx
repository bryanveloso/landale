import { useEffect } from 'react'
import { createFileRoute } from '@tanstack/react-router'
import { trpcClient } from '@/lib/trpc'
import { emoteQueue } from '@/lib/emote-queue'

import { EmoteRain } from '@/components/emotes/emote-rain'
import { ErrorBoundary } from '@/components/error-boundary'

export const Route = createFileRoute('/(full)/emoterain')({
  component: RouteComponent
})

function RouteComponent() {
  useEffect(() => {
    const subscription = trpcClient.twitch.onMessage.subscribe(undefined, {
      onData: (data) => {
        // Process message parts to find emotes
        if (data.messageParts) {
          data.messageParts.forEach((part) => {
            if (part.type === 'emote' && part.emote) {
              // Queue the emote
              emoteQueue.queueEmote(part.emote.id)
            }
          })
        }
      }
    })

    return () => {
      subscription.unsubscribe()
    }
  }, [])

  return (
    <ErrorBoundary>
      <EmoteRain />
    </ErrorBoundary>
  )
}
