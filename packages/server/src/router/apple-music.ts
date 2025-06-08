import { router, publicProcedure } from '@/trpc'
import { z } from 'zod'
import { appleMusicService } from '@/services/apple-music'
import { logger } from '@/lib/logger'

export const appleMusicRouter = router({
  // Receive updates from host service
  updateFromHost: publicProcedure
    .input(z.object({
      playbackState: z.enum(['playing', 'paused', 'stopped']).optional(),
      currentSong: z.object({
        title: z.string(),
        artist: z.string(),
        album: z.string(),
        duration: z.number(),
        playbackTime: z.number()
      }).optional()
    }))
    .mutation(({ input }) => {
      appleMusicService.updateFromHost(input)
      return { success: true }
    })
})