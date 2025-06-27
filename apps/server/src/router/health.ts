import { router, publicProcedure } from '@/trpc'
import { createPollingSubscription } from '@/lib/subscription'

export const healthRouter = router({
  check: publicProcedure.subscription(async function* (opts) {
    yield* createPollingSubscription(opts, {
      getData: () => ({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        version: '0.3.0'
      }),
      intervalMs: 5000
    })
  })
})
