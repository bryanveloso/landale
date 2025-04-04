import { initTRPC } from '@trpc/server'
import { eventEmitter } from './events'

// Initialize tRPC.
const t = initTRPC.create()
const router = t.router
const publicProcedure = t.procedure

export const twitchRouter = router({
  onMessage: publicProcedure.subscription(async function* () {
    const stream = eventEmitter.events('twitch:message')
    try {
      for await (const data of stream) {
        yield data
      }
    } finally {
      // Cleanup happens automatically when the client unsubscribes.
    }
  })
})

export const appRouter = router({
  twitch: twitchRouter
})

export type AppRouter = typeof appRouter
