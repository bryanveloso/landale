import { router, publicProcedure } from '@/trpc'
import { z } from 'zod'
import { createPollingSubscription, createEventSubscription } from '@/lib/subscription'
import { getHealthMonitor } from '@/lib/health'
import { TRPCError } from '@trpc/server'

export const healthRouter = router({
  // Basic health check (legacy, kept for compatibility)
  check: publicProcedure.subscription(async function* (opts) {
    yield* createPollingSubscription(opts, {
      getData: () => ({
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        version: '0.7.0'
      }),
      intervalMs: 5000
    })
  }),
  
  // Get current health status of all services
  getStatus: publicProcedure.query(() => {
    const healthMonitor = getHealthMonitor()
    return healthMonitor.getHealthStatus()
  }),
  
  // Get health status for a specific service
  getServiceHealth: publicProcedure
    .input(
      z.object({
        service: z.string()
      })
    )
    .query(({ input }) => {
      const healthMonitor = getHealthMonitor()
      const health = healthMonitor.getServiceHealth(input.service)
      
      if (!health) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: `Service '${input.service}' not found`
        })
      }
      
      return health
    }),
  
  // Stream health status updates
  onHealthUpdate: publicProcedure.subscription(async function* ({ ctx, signal }) {
    const log = ctx.logger.child({ module: 'health-router', subscription: 'onHealthUpdate' })
    
    try {
      log.debug('Starting health update subscription')
      
      yield* createEventSubscription(
        { signal },
        {
          events: ['health:status', 'health:alert'],
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream health updates'
            })
        }
      )
    } finally {
      log.debug('Health update subscription ended')
    }
  })
})
