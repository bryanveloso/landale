import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter } from '@/events'
import { createLogger } from '@landale/logger'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'twitch-router' })

export const twitchRouter = router({
  onMessage: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:message')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch message subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch messages',
        cause: error
      })
    } finally {
      log.debug('Twitch message subscription ended')
    }
  }),

  onFollow: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:follow')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch follow subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch follows',
        cause: error
      })
    }
  }),

  onSubscription: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:subscription')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch subscription subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch subscriptions',
        cause: error
      })
    }
  }),

  onSubscriptionGift: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:subscription:gift')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch gift subscription subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch gift subscriptions',
        cause: error
      })
    }
  }),

  onSubscriptionMessage: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:subscription:message')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch resub subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch resubs',
        cause: error
      })
    }
  }),

  onRedemption: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:redemption')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch redemption subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch redemptions',
        cause: error
      })
    }
  }),

  onStreamOnline: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:stream:online')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch stream online subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch online events',
        cause: error
      })
    }
  }),

  onStreamOffline: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:stream:offline')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch stream offline subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch offline events',
        cause: error
      })
    }
  })
})
