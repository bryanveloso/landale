import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter } from '@/events'
import { createLogger } from '@/lib/logger'

const log = createLogger('twitch')

export const twitchRouter = router({
  onMessage: publicProcedure.subscription(async function* (opts) {
    try {
      const stream = eventEmitter.events('twitch:message')

      for await (const data of stream) {
        if (opts.signal?.aborted) break
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