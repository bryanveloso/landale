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
          case 'obs:scene:current-changed':
            return {
              type: 'sceneChanged',
              scene: data.sceneName,
              previousScene: obsService.getState().scenes.current
            }
          case 'obs:scene:list-changed':
            return {
              type: 'scenesListUpdated',
              scenes: data.scenes
            }
          case 'obs:stream:state-changed':
            return {
              type: 'streamingStateChanged',
              active: data.outputActive,
              timecode: data.outputTimecode
            }
          case 'obs:studio-mode:changed':
            return {
              type: 'studioModeToggled',
              enabled: data.studioModeEnabled
            }
          default:
            return null
        }
      }
    })
  }),

  // HTTP endpoint for initial state
  getState: publicProcedure.query(async () => {
    return obsService.getState()
  })
})
