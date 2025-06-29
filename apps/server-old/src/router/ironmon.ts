import { z } from 'zod'
import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter } from '@/events'
import { createLogger } from '@landale/logger'
import { createPollingSubscription } from '@/lib/subscription'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'ironmon-router' })

export const ironmonRouter = router({
  checkpointStats: publicProcedure.input(z.object({ checkpointId: z.number() })).subscription(async function* ({
    input,
    signal: _signal
  }) {
    const { databaseService } = await import('@/services/database')
    const stats = await databaseService.getCheckpointStats(input.checkpointId)
    yield stats
  }),

  recentResults: publicProcedure
    .input(
      z.object({
        limit: z.number().min(1).max(100).default(10),
        cursor: z.number().optional()
      })
    )
    .subscription(async function* ({ input, signal }) {
      const { databaseService } = await import('@/services/database')
      // Send initial results
      const results = await databaseService.getRecentResults(input.limit, input.cursor)
      yield results

      // Then poll for updates every 10 seconds
      yield* createPollingSubscription(
        { signal },
        {
          getData: async () => databaseService.getRecentResults(input.limit, input.cursor),
          intervalMs: 10000
        }
      )
    }),

  activeChallenge: publicProcedure.input(z.object({ seedId: z.string() })).subscription(async function* ({
    input,
    signal
  }) {
    const { databaseService } = await import('@/services/database')
    // Send initial data
    const challenge = await databaseService.getActiveChallenge(input.seedId)
    yield challenge

    // Then poll for updates every 5 seconds
    yield* createPollingSubscription(
      { signal },
      {
        getData: async () => databaseService.getActiveChallenge(input.seedId),
        intervalMs: 5000
      }
    )
  }),

  onInit: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('ironmon:init')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in IronMON init subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON init events'
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
      log.error('Error in IronMON seed subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON seed events'
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
      log.error('Error in IronMON checkpoint subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON checkpoint events'
      })
    }
  }),

  onMessage: publicProcedure.subscription(async function* (opts) {
    const unsubscribers: (() => void)[] = []
    const queue: unknown[] = []
    let resolveNext: ((value: IteratorResult<unknown>) => void) | null = null

    try {
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

      while (!opts.signal?.aborted) {
        if (queue.length > 0) {
          yield queue.shift()
        } else {
          yield await new Promise<unknown>((resolve) => {
            resolveNext = (result) => {
              resolve(result.value)
            }
          })
        }
      }
    } catch (error) {
      log.error('Error in combined IronMON subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON events'
      })
    } finally {
      unsubscribers.forEach((fn) => {
        fn()
      })
      log.debug('Combined IronMON subscription ended')
    }
  })
})
