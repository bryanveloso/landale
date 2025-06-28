import { z } from 'zod'
import { createLogger } from '@landale/logger'
import { displayManager } from '@/services/display-manager'
import type { AppleMusicNowPlaying } from '@landale/shared'

// Schema for Apple Music now playing data
export const appleMusicNowPlayingSchema = z.object({
  isEnabled: z.boolean().default(false),
  isAuthorized: z.boolean().default(true), // Always authorized with host service
  currentSong: z
    .object({
      title: z.string(),
      artist: z.string(),
      album: z.string(),
      duration: z.number(), // in seconds
      playbackTime: z.number() // in seconds
    })
    .optional(),
  playbackState: z.enum(['playing', 'paused', 'stopped']).optional()
})

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'apple-music' })

class AppleMusicService {
  private currentData: AppleMusicNowPlaying = {
    isEnabled: true, // Default to enabled since it's controlled by host service
    isAuthorized: true // Always authorized with AppleScript approach
  }

  init() {
    log.info('Initializing Apple Music service (host-based)')
    // Don't update display manager here - it's already initialized in index.ts
  }

  // Update from host service
  updateFromHost(data: Partial<AppleMusicNowPlaying>) {
    // Update current data
    this.currentData = {
      ...this.currentData,
      ...data,
      isEnabled: true,
      isAuthorized: true
    }

    // Send update to display manager
    displayManager.update('appleMusic', this.currentData)

    log.debug('Apple Music update from host', {
      metadata: {
        playbackState: data.playbackState,
        song: data.currentSong?.title
      }
    })
  }

  updateConfig(config: Partial<AppleMusicNowPlaying>) {
    this.currentData = {
      ...this.currentData,
      ...config
    }
    // Don't update display manager here - this is called BY the display manager
  }

  getCurrentData(): AppleMusicNowPlaying {
    return this.currentData
  }
}

export const appleMusicService = new AppleMusicService()

// Export getter for health checks
export function getAppleMusicService(): AppleMusicService {
  return appleMusicService
}
