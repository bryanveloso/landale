import { z } from 'zod'
import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter } from '@/events'
import { createLogger } from '@/lib/logger'
import { formatUptime, formatBytes } from '@/lib/utils'
import { createEventSubscription, createPollingSubscription } from '@/lib/subscription'
import { emoteRainConfigSchema, type SystemStatus, type ActivityEvent } from '@/types/control'

const log = createLogger('control')

// In-memory storage
const overlayConfigs = {
  emoteRain: emoteRainConfigSchema.parse({})
}

const connectedSources = new Map<
  string,
  {
    id: string
    type: string
    connectedAt: Date
    lastPing: Date
  }
>()

// Helper functions
const getSystemStatus = (): SystemStatus => {
  const uptime = process.uptime()
  const memoryUsage = process.memoryUsage()

  return {
    status: 'online',
    timestamp: new Date().toISOString(),
    uptime: {
      seconds: uptime,
      formatted: formatUptime(uptime)
    },
    memory: {
      rss: formatBytes(memoryUsage.rss),
      heapTotal: formatBytes(memoryUsage.heapTotal),
      heapUsed: formatBytes(memoryUsage.heapUsed),
      external: formatBytes(memoryUsage.external)
    },
    version: process.env.npm_package_version || '0.3.0'
  }
}

// Helper function for future use
// const getBrowserSources = (): BrowserSource[] => {
//   return Array.from(connectedSources.values()).map(source => ({
//     ...source,
//     connectedAt: source.connectedAt.toISOString(),
//     lastPing: source.lastPing.toISOString()
//   }))
// }

export const controlRouter = router({
  system: router({
    onStatusUpdate: publicProcedure.subscription(async function* (opts) {
      yield* createPollingSubscription(opts, {
        getData: getSystemStatus,
        intervalMs: 5000,
        onError: (_error) =>
          new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream status updates'
          })
      })
    }),

    onSourceUpdate: publicProcedure.subscription(async function* (opts) {
      yield* createEventSubscription(opts, {
        events: ['control:source:connected', 'control:source:disconnected', 'control:source:ping'],
        transform: (eventType, data) => ({ type: eventType, data }),
        onError: (_error) =>
          new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream source updates'
          })
      })
    })
  }),

  config: router({
    emoteRain: router({
      onConfigUpdate: publicProcedure.subscription(async function* (opts) {
        // Send initial config
        yield overlayConfigs.emoteRain

        // Stream updates
        yield* createEventSubscription(opts, {
          events: ['config:emoteRain:updated'],
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream config updates'
            })
        })
      }),

      update: publicProcedure.input(emoteRainConfigSchema.partial()).mutation(async ({ input }) => {
        overlayConfigs.emoteRain = { ...overlayConfigs.emoteRain, ...input }

        eventEmitter.emit('config:emoteRain:updated', overlayConfigs.emoteRain)
        log.info('Emote rain config updated', input)

        return overlayConfigs.emoteRain
      }),

      burst: publicProcedure
        .input(
          z.object({
            emoteId: z.string().optional(),
            count: z.number().min(1).max(50).default(10)
          })
        )
        .mutation(async ({ input }) => {
          eventEmitter.emit('emoteRain:burst', input)
          log.info('Manual emote burst triggered', input)
          return { success: true }
        }),

      clear: publicProcedure.mutation(async () => {
        eventEmitter.emit('emoteRain:clear', undefined)
        log.info('Emote rain cleared')
        return { success: true }
      })
    })
  }),

  stream: router({
    chat: publicProcedure.subscription(async function* (opts) {
      yield* createEventSubscription(opts, {
        events: ['twitch:message'],
        onError: (_error) =>
          new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream chat messages'
          })
      })
    }),

    activity: publicProcedure.subscription(async function* (opts) {
      yield* createEventSubscription(opts, {
        events: [
          'twitch:message',
          'twitch:cheer',
          'ironmon:init',
          'ironmon:checkpoint',
          'ironmon:seed',
          'config:emoteRain:updated'
        ],
        transform: (eventType, data): ActivityEvent => ({
          id: Date.now().toString(),
          type: eventType,
          timestamp: new Date().toISOString(),
          data
        }),
        onError: (_error) =>
          new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream activity events'
          })
      })
    }),

    ironmon: router({
      current: publicProcedure.query(async () => {
        return {
          active: false,
          seed: null,
          checkpoint: null
        }
      }),

      onUpdate: publicProcedure.subscription(async function* (opts) {
        yield* createEventSubscription(opts, {
          events: ['ironmon:init', 'ironmon:seed', 'ironmon:checkpoint', 'ironmon:location'],
          transform: (eventType, data) => ({ type: eventType, data }),
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream IronMON updates'
            })
        })
      })
    })
  }),

  actions: router({
    reloadSource: publicProcedure.input(z.object({ sourceId: z.string() })).mutation(async ({ input }) => {
      eventEmitter.emit('source:reload', input.sourceId)
      log.info('Source reload requested', input)
      return { success: true }
    })
  })
})

// Event handlers for source tracking
eventEmitter.on('control:source:connected', ({ id, type }: { id: string; type: string }) => {
  connectedSources.set(id, {
    id,
    type,
    connectedAt: new Date(),
    lastPing: new Date()
  })
})

eventEmitter.on('control:source:disconnected', ({ id }: { id: string }) => {
  connectedSources.delete(id)
})

eventEmitter.on('control:source:ping', ({ id }: { id: string }) => {
  const source = connectedSources.get(id)
  if (source) {
    source.lastPing = new Date()
  }
})
