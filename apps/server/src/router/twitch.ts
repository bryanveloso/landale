import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter } from '@/events'

export const twitchRouter = router({
  onMessage: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onMessage' })
    
    try {
      log.debug('Starting Twitch message subscription')
      const stream = eventEmitter.events('twitch:message')

      for await (const data of stream) {
        if (signal?.aborted) break
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

  onFollow: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onFollow' })
    
    try {
      log.debug('Starting Twitch follow subscription')
      const stream = eventEmitter.events('twitch:follow')

      for await (const data of stream) {
        if (signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch follow subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch follows',
        cause: error
      })
    } finally {
      log.debug('Twitch follow subscription ended')
    }
  }),

  onSubscription: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onSubscription' })
    
    try {
      log.debug('Starting Twitch subscription subscription')
      const stream = eventEmitter.events('twitch:subscription')

      for await (const data of stream) {
        if (signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch subscription subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch subscriptions',
        cause: error
      })
    } finally {
      log.debug('Twitch subscription subscription ended')
    }
  }),

  onSubscriptionGift: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onSubscriptionGift' })
    
    try {
      log.debug('Starting Twitch gift subscription subscription')
      const stream = eventEmitter.events('twitch:subscription:gift')

      for await (const data of stream) {
        if (signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch gift subscription subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch gift subscriptions',
        cause: error
      })
    } finally {
      log.debug('Twitch gift subscription subscription ended')
    }
  }),

  onSubscriptionMessage: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onSubscriptionMessage' })
    
    try {
      log.debug('Starting Twitch resub subscription')
      const stream = eventEmitter.events('twitch:subscription:message')

      for await (const data of stream) {
        if (signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch resub subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch resubs',
        cause: error
      })
    } finally {
      log.debug('Twitch resub subscription ended')
    }
  }),

  onRedemption: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onRedemption' })
    
    try {
      log.debug('Starting Twitch redemption subscription')
      const stream = eventEmitter.events('twitch:redemption')

      for await (const data of stream) {
        if (signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch redemption subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch redemptions',
        cause: error
      })
    } finally {
      log.debug('Twitch redemption subscription ended')
    }
  }),

  onStreamOnline: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onStreamOnline' })
    
    try {
      log.debug('Starting Twitch stream online subscription')
      const stream = eventEmitter.events('twitch:stream:online')

      for await (const data of stream) {
        if (signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch stream online subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch online events',
        cause: error
      })
    } finally {
      log.debug('Twitch stream online subscription ended')
    }
  }),

  onStreamOffline: publicProcedure.subscription(async function* ({ signal, ctx }) {
    const log = ctx.logger.child({ module: 'twitch-router', subscription: 'onStreamOffline' })
    
    try {
      log.debug('Starting Twitch stream offline subscription')
      const stream = eventEmitter.events('twitch:stream:offline')

      for await (const data of stream) {
        if (signal?.aborted) break
        yield data
      }
    } catch (error) {
      log.error('Error in Twitch stream offline subscription', { error: error as Error })
      throw new TRPCError({
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to stream Twitch offline events',
        cause: error
      })
    } finally {
      log.debug('Twitch stream offline subscription ended')
    }
  })
})
