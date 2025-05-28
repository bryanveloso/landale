import { z } from 'zod'
import { router, publicProcedure } from '../trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter } from '../events'
import { createLogger } from '../lib/logger'
import { formatUptime, formatBytes } from '../lib/utils'

const log = createLogger('control')

// Configuration schemas for overlays that support configuration
const emoteRainConfigSchema = z.object({
  size: z.number().min(28).max(224).default(112),
  lifetime: z.number().min(1000).max(60000).default(30000),
  gravity: z.number().min(0.1).max(3).default(1),
  restitution: z.number().min(0).max(1).default(0.4),
  friction: z.number().min(0).max(1).default(0.3),
  airFriction: z.number().min(0).max(0.05).default(0.001),
  spawnDelay: z.number().min(50).max(1000).default(100),
  maxEmotes: z.number().min(10).max(500).default(200),
  rotationSpeed: z.number().min(0).max(1).default(0.2)
})

// In-memory storage (would be persisted to database in production)
const overlayConfigs = {
  emoteRain: emoteRainConfigSchema.parse({})
}

// Track connected browser sources
const connectedSources = new Map<string, {
  id: string
  type: string
  connectedAt: Date
  lastPing: Date
}>()

export const controlRouter = router({
  // System monitoring
  system: router({
    status: publicProcedure.query(async () => {
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
    }),

    // Subscription for real-time status updates
    onStatusUpdate: publicProcedure.subscription(async function* (opts) {
      try {
        while (true) {
          if (opts.signal?.aborted) break

          const uptime = process.uptime()
          const memoryUsage = process.memoryUsage()

          yield {
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

          // Update every 5 seconds
          await new Promise((resolve) => setTimeout(resolve, 5000))
        }
      } catch (error) {
        log.error('Error in status subscription', error)
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'Failed to stream status updates'
        })
      }
    }),

    // Get connected browser sources
    sources: publicProcedure.query(() => {
      return Array.from(connectedSources.values()).map((source) => ({
        ...source,
        connectedAt: source.connectedAt.toISOString(),
        lastPing: source.lastPing.toISOString()
      }))
    }),

    // Track browser source connections
    onSourceUpdate: publicProcedure.subscription(async function* (opts) {
      const unsubscribers: (() => void)[] = []
      const queue: unknown[] = []
      let resolveNext: ((value: IteratorResult<unknown>) => void) | null = null

      try {
        // Subscribe to source events
        const eventTypes = ['control:source:connected', 'control:source:disconnected', 'control:source:ping'] as const

        for (const eventType of eventTypes) {
          const unsubscribe = eventEmitter.on(eventType, (data) => {
            if (resolveNext) {
              resolveNext({ value: { type: eventType, data }, done: false })
              resolveNext = null
            } else {
              queue.push({ type: eventType, data })
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
        log.error('Error in source update subscription', error)
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'Failed to stream source updates'
        })
      } finally {
        unsubscribers.forEach((fn) => fn())
      }
    })
  }),

  // Overlay configurations
  config: router({
    // Emote Rain configuration
    emoteRain: router({
      get: publicProcedure.query(() => overlayConfigs.emoteRain),

      // Subscription for real-time config updates
      onConfigUpdate: publicProcedure.subscription(async function* (opts) {
        // Set up event listener for config updates
        const queue: unknown[] = []
        let resolveNext: ((value: IteratorResult<unknown>) => void) | null = null
        let unsubscribe: (() => void) | null = null

        try {
          // Send initial config
          yield overlayConfigs.emoteRain

          unsubscribe = eventEmitter.on('config:emoteRain:updated', (config) => {
            if (resolveNext) {
              resolveNext({ value: config, done: false })
              resolveNext = null
            } else {
              queue.push(config)
            }
          })

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
          log.error('Error in emote rain config subscription', error)
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream config updates'
          })
        } finally {
          // Clean up event listeners
          unsubscribe?.()
        }
      }),

      update: publicProcedure.input(emoteRainConfigSchema.partial()).mutation(async ({ input }) => {
        overlayConfigs.emoteRain = { ...overlayConfigs.emoteRain, ...input }

        // Notify connected emote rain overlays
        eventEmitter.emit('config:emoteRain:updated', overlayConfigs.emoteRain)
        log.info('Emote rain config updated', input)

        return overlayConfigs.emoteRain
      }),

      // Manual emote burst trigger
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

      // Clear all emotes
      clear: publicProcedure.mutation(async () => {
        eventEmitter.emit('emoteRain:clear', undefined)
        log.info('Emote rain cleared')
        return { success: true }
      })
    })

    // Future overlay configs would go here
    // Example:
    // omnibar: router({ ... })
  }),

  // Stream monitoring
  stream: router({
    // Relay Twitch chat for dashboard display
    chat: publicProcedure.subscription(async function* (opts) {
      try {
        const stream = eventEmitter.events('twitch:message')

        for await (const data of stream) {
          if (opts.signal?.aborted) break
          yield data
        }
      } catch (error) {
        log.error('Error in chat subscription', error)
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'Failed to stream chat messages'
        })
      }
    }),

    // Activity feed combining multiple event sources
    activity: publicProcedure.subscription(async function* (opts) {
      const unsubscribers: (() => void)[] = []
      const queue: unknown[] = []
      let resolveNext: ((value: IteratorResult<unknown>) => void) | null = null

      try {
        // Subscribe to relevant events
        const eventTypes = [
          'twitch:message',
          'twitch:cheer',
          'ironmon:init',
          'ironmon:checkpoint',
          'ironmon:seed',
          'config:emoteRain:updated'
        ] as const

        for (const eventType of eventTypes) {
          const unsubscribe = eventEmitter.on(eventType, (data) => {
            const activity = {
              id: Date.now().toString(),
              type: eventType,
              timestamp: new Date().toISOString(),
              data
            }

            if (resolveNext) {
              resolveNext({ value: activity, done: false })
              resolveNext = null
            } else {
              queue.push(activity)
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
      } finally {
        unsubscribers.forEach((fn) => fn())
      }
    }),

    // IronMON data (read-only)
    ironmon: router({
      // Current game state
      current: publicProcedure.query(async () => {
        // This would query the current IronMON state
        // For now, return empty state
        return {
          active: false,
          seed: null,
          checkpoint: null
        }
      }),

      // Subscribe to IronMON updates
      onUpdate: publicProcedure.subscription(async function* (opts) {
        const unsubscribers: (() => void)[] = []
        const queue: unknown[] = []
        let resolveNext: ((value: IteratorResult<unknown>) => void) | null = null

        try {
          // Subscribe to IronMON events
          const eventTypes = ['ironmon:init', 'ironmon:seed', 'ironmon:checkpoint', 'ironmon:location'] as const

          for (const eventType of eventTypes) {
            const unsubscribe = eventEmitter.on(eventType, (data) => {
              if (resolveNext) {
                resolveNext({ value: { type: eventType, data }, done: false })
                resolveNext = null
              } else {
                queue.push({ type: eventType, data })
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
          log.error('Error in IronMON subscription', error)
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream IronMON updates'
          })
        } finally {
          unsubscribers.forEach((fn) => fn())
        }
      })
    })
  }),

  // Actions
  actions: router({
    // Force reload a specific browser source
    reloadSource: publicProcedure
      .input(
        z.object({
          sourceId: z.string()
        })
      )
      .mutation(async ({ input }) => {
        eventEmitter.emit('source:reload', input.sourceId)
        log.info('Source reload requested', input)
        return { success: true }
      })
  })
})

// Helper to register browser source connections
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
