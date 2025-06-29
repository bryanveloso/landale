import { router, publicProcedure } from '@/trpc'
import { z } from 'zod'
import { performanceMonitor } from '@/lib/performance'
import { auditLogger, AuditCategory, AuditAction } from '@/lib/audit'
import { TRPCError } from '@trpc/server'
import { createEventSubscription } from '@/lib/subscription'

export const monitoringRouter = router({
  // Performance metrics
  performance: router({
    // Get recent metrics for a specific operation
    getMetrics: publicProcedure
      .input(
        z.object({
          operation: z.string(),
          category: z.enum(['obsCall', 'database', 'api', 'websocket'])
        })
      )
      .query(({ input }) => {
        const metrics = performanceMonitor.getRecentMetrics(input.operation, input.category)
        const averages = performanceMonitor.getAverageMetrics(input.operation, input.category)

        return {
          metrics,
          averages,
          count: metrics.length
        }
      }),

    // Stream performance metrics in real-time
    onMetrics: publicProcedure.subscription(async function* ({ ctx, signal }) {
      const log = ctx.logger.child({ module: 'monitoring-router', subscription: 'performance.onMetrics' })

      try {
        log.debug('Starting performance metrics subscription')

        yield* createEventSubscription(
          { signal },
          {
            events: ['performance:metric', 'performance:critical'],
            onError: (_error) =>
              new TRPCError({
                code: 'INTERNAL_SERVER_ERROR',
                message: 'Failed to stream performance metrics'
              })
          }
        )
      } finally {
        log.debug('Performance metrics subscription ended')
      }
    }),

    // Stream health metrics
    onStreamHealth: publicProcedure.subscription(async function* ({ ctx, signal }) {
      const log = ctx.logger.child({ module: 'monitoring-router', subscription: 'performance.onStreamHealth' })

      try {
        log.debug('Starting stream health subscription')

        yield* createEventSubscription(
          { signal },
          {
            events: ['streamHealth:metric', 'streamHealth:alert'],
            onError: (_error) =>
              new TRPCError({
                code: 'INTERNAL_SERVER_ERROR',
                message: 'Failed to stream health metrics'
              })
          }
        )
      } finally {
        log.debug('Stream health subscription ended')
      }
    })
  }),

  // Audit logs
  audit: router({
    // Get recent audit events
    getRecentEvents: publicProcedure
      .input(
        z.object({
          limit: z.number().min(1).max(1000).default(100),
          category: z.nativeEnum(AuditCategory).optional(),
          action: z.nativeEnum(AuditAction).optional()
        })
      )
      .query(async ({ input }) => {
        const events = await auditLogger.getRecentEvents(input.limit)

        // Filter by category and action if provided
        let filtered = events
        if (input.category) {
          filtered = filtered.filter((e) => e.category === input.category)
        }
        if (input.action) {
          filtered = filtered.filter((e) => e.action === input.action)
        }

        return filtered
      }),

    // Stream audit events in real-time
    onEvents: publicProcedure.subscription(async function* ({ ctx, signal }) {
      const log = ctx.logger.child({ module: 'monitoring-router', subscription: 'audit.onEvents' })

      try {
        log.debug('Starting audit events subscription')

        yield* createEventSubscription(
          { signal },
          {
            events: ['audit:event'],
            onError: (_error) =>
              new TRPCError({
                code: 'INTERNAL_SERVER_ERROR',
                message: 'Failed to stream audit events'
              })
          }
        )
      } finally {
        log.debug('Audit events subscription ended')
      }
    })
  })
})
