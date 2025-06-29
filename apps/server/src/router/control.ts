import { z } from 'zod'
import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { eventEmitter, emitEventWithCorrelation } from '@/events'
import { formatUptime, formatBytes } from '@/lib/utils'
import { createEventSubscription, createPollingSubscription } from '@/lib/subscription'
import { emoteRainConfigSchema, type SystemStatus, type ActivityEvent } from '@/types/control'
import { obsService } from '@/services/obs'

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

      update: publicProcedure.input(emoteRainConfigSchema.partial()).subscription(async function* ({ input, ctx }) {
        const log = ctx.logger.child({ module: 'control-router', subscription: 'emoteRain.update' })

        overlayConfigs.emoteRain = { ...overlayConfigs.emoteRain, ...input }

        void emitEventWithCorrelation('config:emoteRain:updated', overlayConfigs.emoteRain, ctx.correlationId)
        log.info('Emote rain config updated', { metadata: { config: input } })

        yield overlayConfigs.emoteRain
      }),

      burst: publicProcedure
        .input(
          z.object({
            emoteId: z.string().optional(),
            count: z.number().min(1).max(50).default(10)
          })
        )
        .subscription(async function* ({ input, ctx }) {
          const log = ctx.logger.child({ module: 'control-router', subscription: 'emoteRain.burst' })

          void emitEventWithCorrelation('emoteRain:burst', input, ctx.correlationId)
          log.info('Manual emote burst triggered', { metadata: { emoteId: input.emoteId, count: input.count } })
          yield { success: true }
        }),

      clear: publicProcedure.subscription(async function* ({ ctx }) {
        const log = ctx.logger.child({ module: 'control-router', subscription: 'emoteRain.clear' })

        void emitEventWithCorrelation('emoteRain:clear', undefined, ctx.correlationId)
        log.info('Emote rain cleared')
        yield { success: true }
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
      current: publicProcedure.subscription(async function* () {
        yield {
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

  obs: router({
    // Connection status
    onConnectionUpdate: publicProcedure.subscription(async function* (opts) {
      // Send initial state
      yield obsService.getState().connection

      // Stream updates
      yield* createEventSubscription(opts, {
        events: ['obs:connection:changed'],
        onError: (_error) =>
          new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream OBS connection updates'
          })
      })
    }),

    // Scene management
    scenes: router({
      onScenesUpdate: publicProcedure.subscription(async function* (opts) {
        // Send initial state
        yield obsService.getState().scenes

        // Stream updates
        yield* createEventSubscription(opts, {
          events: [
            'obs:scenes:updated',
            'obs:scene:current-changed',
            'obs:scene:preview-changed',
            'obs:scene:list-changed'
          ],
          transform: () => obsService.getState().scenes,
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream OBS scene updates'
            })
        })
      }),

      setCurrentScene: publicProcedure.input(z.object({ sceneName: z.string() })).mutation(async ({ input, ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'setCurrentScene' })

        try {
          await obsService.setCurrentScene(input.sceneName, ctx.correlationId)
          log.info('Current scene changed', { metadata: { sceneName: input.sceneName } })
          return { success: true }
        } catch (error) {
          log.error('Failed to set current scene', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to set current scene'
          })
        }
      }),

      setPreviewScene: publicProcedure.input(z.object({ sceneName: z.string() })).mutation(async ({ input, ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'setPreviewScene' })

        try {
          await obsService.setPreviewScene(input.sceneName, ctx.correlationId)
          log.info('Preview scene changed', { metadata: { sceneName: input.sceneName } })
          return { success: true }
        } catch (error) {
          log.error('Failed to set preview scene', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to set preview scene'
          })
        }
      }),

      createScene: publicProcedure.input(z.object({ sceneName: z.string() })).mutation(async ({ input, ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'createScene' })

        try {
          await obsService.createScene(input.sceneName, ctx.correlationId)
          log.info('Scene created', { metadata: { sceneName: input.sceneName } })
          return { success: true }
        } catch (error) {
          log.error('Failed to create scene', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to create scene'
          })
        }
      }),

      removeScene: publicProcedure.input(z.object({ sceneName: z.string() })).mutation(async ({ input, ctx }) => {
        try {
          await obsService.removeScene(input.sceneName)
          ctx.logger.info('Scene removed', { metadata: { sceneName: input.sceneName } })
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to remove scene', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to remove scene'
          })
        }
      })
    }),

    // Streaming controls
    streaming: router({
      onStreamingUpdate: publicProcedure.subscription(async function* (opts) {
        // Send initial state
        yield obsService.getState().streaming

        // Stream updates
        yield* createEventSubscription(opts, {
          events: ['obs:streaming:updated', 'obs:stream:state-changed'],
          transform: () => obsService.getState().streaming,
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream OBS streaming updates'
            })
        })
      }),

      start: publicProcedure.mutation(async ({ ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'streaming.start' })

        try {
          await obsService.startStream(ctx.correlationId)
          log.info('Stream started')
          return { success: true }
        } catch (error) {
          log.error('Failed to start stream', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to start stream'
          })
        }
      }),

      stop: publicProcedure.mutation(async ({ ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'streaming.stop' })

        try {
          await obsService.stopStream(ctx.correlationId)
          log.info('Stream stopped')
          return { success: true }
        } catch (error) {
          log.error('Failed to stop stream', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to stop stream'
          })
        }
      })
    }),

    // Recording controls
    recording: router({
      onRecordingUpdate: publicProcedure.subscription(async function* (opts) {
        // Send initial state
        yield obsService.getState().recording

        // Stream updates
        yield* createEventSubscription(opts, {
          events: ['obs:recording:updated', 'obs:record:state-changed'],
          transform: () => obsService.getState().recording,
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream OBS recording updates'
            })
        })
      }),

      start: publicProcedure.mutation(async ({ ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'recording.start' })

        try {
          await obsService.startRecording(ctx.correlationId)
          log.info('Recording started')
          return { success: true }
        } catch (error) {
          log.error('Failed to start recording', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to start recording'
          })
        }
      }),

      stop: publicProcedure.mutation(async ({ ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'recording.stop' })

        try {
          await obsService.stopRecording(ctx.correlationId)
          log.info('Recording stopped')
          return { success: true }
        } catch (error) {
          log.error('Failed to stop recording', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to stop recording'
          })
        }
      }),

      pause: publicProcedure.mutation(async ({ ctx }) => {
        const log = ctx.logger.child({ module: 'control-router', method: 'recording.pause' })

        try {
          await obsService.pauseRecording(ctx.correlationId)
          log.info('Recording paused')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to pause recording', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to pause recording'
          })
        }
      }),

      resume: publicProcedure.mutation(async ({ ctx }) => {
        try {
          await obsService.resumeRecording()
          ctx.logger.info('Recording resumed')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to resume recording', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to resume recording'
          })
        }
      })
    }),

    // Studio mode controls
    studioMode: router({
      onStudioModeUpdate: publicProcedure.subscription(async function* (opts) {
        // Send initial state
        yield obsService.getState().studioMode

        // Stream updates
        yield* createEventSubscription(opts, {
          events: ['obs:studio-mode:updated', 'obs:studio-mode:changed'],
          transform: () => obsService.getState().studioMode,
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream OBS studio mode updates'
            })
        })
      }),

      setEnabled: publicProcedure.input(z.object({ enabled: z.boolean() })).mutation(async ({ input, ctx }) => {
        try {
          await obsService.setStudioModeEnabled(input.enabled)
          ctx.logger.info('Studio mode changed', { metadata: { enabled: input.enabled } })
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to set studio mode', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to set studio mode'
          })
        }
      }),

      triggerTransition: publicProcedure.mutation(async ({ ctx }) => {
        try {
          await obsService.triggerStudioModeTransition()
          ctx.logger.info('Studio mode transition triggered')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to trigger transition', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to trigger transition'
          })
        }
      })
    }),

    // Virtual camera controls
    virtualCam: router({
      onVirtualCamUpdate: publicProcedure.subscription(async function* (opts) {
        // Send initial state
        yield obsService.getState().virtualCam || { active: false }

        // Stream updates
        yield* createEventSubscription(opts, {
          events: ['obs:virtual-cam:updated', 'obs:virtual-cam:changed'],
          transform: () => obsService.getState().virtualCam || { active: false },
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream OBS virtual cam updates'
            })
        })
      }),

      start: publicProcedure.mutation(async ({ ctx }) => {
        try {
          await obsService.startVirtualCam()
          ctx.logger.info('Virtual camera started')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to start virtual camera', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to start virtual camera'
          })
        }
      }),

      stop: publicProcedure.mutation(async ({ ctx }) => {
        try {
          await obsService.stopVirtualCam()
          ctx.logger.info('Virtual camera stopped')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to stop virtual camera', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to stop virtual camera'
          })
        }
      })
    }),

    // Replay buffer controls
    replayBuffer: router({
      onReplayBufferUpdate: publicProcedure.subscription(async function* (opts) {
        // Send initial state
        yield obsService.getState().replayBuffer || { active: false }

        // Stream updates
        yield* createEventSubscription(opts, {
          events: ['obs:replay-buffer:updated', 'obs:replay-buffer:changed'],
          transform: () => obsService.getState().replayBuffer || { active: false },
          onError: (_error) =>
            new TRPCError({
              code: 'INTERNAL_SERVER_ERROR',
              message: 'Failed to stream OBS replay buffer updates'
            })
        })
      }),

      start: publicProcedure.mutation(async ({ ctx }) => {
        try {
          await obsService.startReplayBuffer()
          ctx.logger.info('Replay buffer started')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to start replay buffer', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to start replay buffer'
          })
        }
      }),

      stop: publicProcedure.mutation(async ({ ctx }) => {
        try {
          await obsService.stopReplayBuffer()
          ctx.logger.info('Replay buffer stopped')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to stop replay buffer', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to stop replay buffer'
          })
        }
      }),

      save: publicProcedure.mutation(async ({ ctx }) => {
        try {
          await obsService.saveReplayBuffer()
          ctx.logger.info('Replay buffer saved')
          return { success: true }
        } catch (error) {
          ctx.logger.error('Failed to save replay buffer', { error: error as Error })
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: error instanceof Error ? error.message : 'Failed to save replay buffer'
          })
        }
      })
    }),

    // General status
    onStateUpdate: publicProcedure.subscription(async function* (opts) {
      // Send initial state
      yield obsService.getState()

      // Stream all OBS updates
      yield* createEventSubscription(opts, {
        events: [
          'obs:connection:changed',
          'obs:scenes:updated',
          'obs:streaming:updated',
          'obs:recording:updated',
          'obs:studio-mode:updated',
          'obs:virtual-cam:updated',
          'obs:replay-buffer:updated'
        ],
        transform: () => obsService.getState(),
        onError: (_error) =>
          new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: 'Failed to stream OBS state updates'
          })
      })
    })
  }),

  actions: router({
    reloadSource: publicProcedure.input(z.object({ sourceId: z.string() })).subscription(async function* ({
      input,
      ctx
    }) {
      void emitEventWithCorrelation('source:reload', input.sourceId, ctx.correlationId)
      ctx.logger.info('Source reload requested', { metadata: input })
      yield { success: true }
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
