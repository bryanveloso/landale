/**
 * Better event-driven approach for OBS updates
 * Instead of sending full state, send specific change events
 */

import { router, publicProcedure } from '@/trpc'
import { createEventSubscription } from '@/lib/subscription'
import { obsService } from '@/services/obs'

export const obsEventsRouter = router({
  // Single subscription for all OBS events
  onOBSEvent: publicProcedure.subscription(async function* (opts) {
    yield* createEventSubscription(opts, {
      events: [
        'obs:scene:current-changed',
        'obs:scene:list-changed',
        'obs:stream:state-changed',
        'obs:studio-mode:changed'
      ],
      transform: (eventType, data) => {
        // Transform raw events into structured updates
        switch (eventType) {
          case 'obs:scene:current-changed': {
            const typedData = data as { sceneName: string; sceneUuid?: string }
            return {
              type: 'sceneChanged',
              scene: typedData.sceneName,
              previousScene: obsService.getState().scenes.current
            }
          }
          case 'obs:scene:list-changed': {
            const typedData = data as { scenes: Array<{ sceneName?: string; sceneIndex?: number; sceneUuid?: string }> }
            return {
              type: 'scenesListUpdated',
              scenes: typedData.scenes
            }
          }
          case 'obs:stream:state-changed': {
            const typedData = data as { outputActive: boolean; outputState: string; outputTimecode?: string }
            return {
              type: 'streamingStateChanged',
              active: typedData.outputActive,
              timecode: typedData.outputTimecode
            }
          }
          case 'obs:studio-mode:changed': {
            const typedData = data as { studioModeEnabled: boolean }
            return {
              type: 'studioModeToggled',
              enabled: typedData.studioModeEnabled
            }
          }
          default:
            return null
        }
      }
    })
  }),

  // HTTP endpoint for initial state
  getState: publicProcedure.query(() => {
    return obsService.getState()
  })
})
