import { initTRPC, TRPCError } from '@trpc/server'
import { z, ZodError } from 'zod'
import { eventEmitter } from './events'
import { createLogger } from './lib/logger'
import { controlRouter } from './router/control'
import { env } from './lib/env'

const log = createLogger('trpc')

// Define context type
interface Context {
  req?: Request
}

// Initialize tRPC with error formatter
const t = initTRPC.context<Context>().create({
  errorFormatter({ shape, error }) {
    return {
      ...shape,
      data: {
        ...shape.data,
        zodError: error.cause instanceof ZodError ? error.cause.flatten() : null
      }
    }
  }
})

export const router = t.router

// Base procedure with error handling and logging
export const publicProcedure = t.procedure.use(async (opts) => {
  const start = Date.now()

  try {
    const result = await opts.next({
      ctx: opts.ctx
    })

    const durationMs = Date.now() - start
    const meta = { path: opts.path, type: opts.type, durationMs }

    if (!result.ok) {
      log.error('Procedure failed', { ...meta, error: result.error })
    }

    return result
  } catch (error) {
    const durationMs = Date.now() - start
    log.error('Unexpected error in procedure', { path: opts.path, type: opts.type, durationMs, error })
    throw error
  }
})

// Authenticated procedure for control API
// Simple API key check since this is for personal use
export const authedProcedure = publicProcedure.use(async (opts) => {
  // Get API key from headers
  const apiKey = opts.ctx.req?.headers?.get('x-api-key')

  const expectedKey = env.CONTROL_API_KEY
  
  if (apiKey !== expectedKey) {
    throw new TRPCError({
      code: 'UNAUTHORIZED',
      message: 'Invalid API key'
    })
  }

  return opts.next()
})

export const twitchRouter = router({
  onMessage: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:message')

      for await (const data of stream) {
        // Validate the stream is still active
        if (opts.signal?.aborted) {
          break
        }
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch message subscription', error)
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch messages',
        cause: error
      })
    } finally {
      log.debug('Twitch message subscription ended')
    }
  })
})

export const ironmonRouter = router({
  // Query procedures for data access
  checkpointStats: publicProcedure
    .input(z.object({ checkpointId: z.number() }))
    .query(async ({ input }) => {
      const { databaseService } = await import('@/services/database')
      return databaseService.getCheckpointStats(input.checkpointId)
    }),

  recentResults: publicProcedure
    .input(z.object({ 
      limit: z.number().min(1).max(100).default(10),
      cursor: z.number().optional()
    }))
    .query(async ({ input }) => {
      const { databaseService } = await import('@/services/database')
      return databaseService.getRecentResults(input.limit, input.cursor)
    }),

  activeChallenge: publicProcedure
    .input(z.object({ seedId: z.string() }))
    .query(async ({ input }) => {
      const { databaseService } = await import('@/services/database')
      return databaseService.getActiveChallenge(input.seedId)
    }),

  // Subscription procedures
  onInit: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('ironmon:init')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in IronMON init subscription', error)
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON init events',
        cause: error
      })
    }
  }),

  onSeed: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('ironmon:seed')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in IronMON seed subscription', error)
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON seed events',
        cause: error
      })
    }
  }),

  onCheckpoint: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('ironmon:checkpoint')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in IronMON checkpoint subscription', error)
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON checkpoint events',
        cause: error
      })
    }
  }),

  // Combined subscription for all IronMON events
  onMessage: publicProcedure.subscription(async function* (opts) {
    const unsubscribers: (() => void)[] = []
    const queue: unknown[] = []
    let resolveNext: ((value: IteratorResult<unknown>) => void) | null = null

    try {
      // Subscribe to all IronMON events
      const eventTypes = ['ironmon:init', 'ironmon:seed', 'ironmon:checkpoint', 'ironmon:location'] as const

      for (const eventType of eventTypes) {
        const unsubscribe = eventEmitter.on(eventType, (data) => {
          if (resolveNext) {
            resolveNext({ value: data, done: false })
            resolveNext = null
          } else {
            queue.push(data)
          }
        })
        unsubscribers.push(unsubscribe)
      }

      while (true) {
        if (opts.signal?.aborted) break

        if (queue.length > 0) {
          yield queue.shift()
        } else {
          // Wait for next event
          yield await new Promise<unknown>((resolve) => {
            resolveNext = (result) => resolve(result.value)
          })
        }
      }
    } catch (error) {
      log.error('Error in combined IronMON subscription', error)
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON events',
        cause: error
      })
    } finally {
      // Cleanup all subscriptions
      unsubscribers.forEach((fn) => fn())
      log.debug('Combined IronMON subscription ended')
    }
  })
})

// Health check procedure
const healthProcedure = publicProcedure.query(async () => {
  return {
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: '0.3.0'
  }
})

export const appRouter = router({
  health: healthProcedure,
  twitch: twitchRouter,
  ironmon: ironmonRouter,
  control: controlRouter
})

// Define the router type
export type AppRouter = typeof appRouter
