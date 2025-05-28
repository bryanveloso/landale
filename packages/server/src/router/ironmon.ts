import { z } from 'zod'
import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter } from '@/events'
import { createLogger } from '@/lib/logger'

const log = createLogger('ironmon')

export const ironmonRouter = router({
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
      log.error('Error in IronMON seed subscription', error)
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
      log.error('Error in IronMON checkpoint subscription', error)
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

      while (true) {
        if (opts.signal?.aborted) break

        if (queue.length > 0) {
          yield queue.shift()
        } else {
          yield await new Promise<unknown>((resolve) => {
            resolveNext = (result) => resolve(result.value)
          })
        }
      }
    } catch (error) {
      log.error('Error in combined IronMON subscription', error)
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream IronMON events'
      })
    } finally {
      unsubscribers.forEach((fn) => fn())
      log.debug('Combined IronMON subscription ended')
    }
  })
})