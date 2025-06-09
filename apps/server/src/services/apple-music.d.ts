import { z } from 'zod'
import type { AppleMusicNowPlaying } from '@landale/shared'
export declare const appleMusicNowPlayingSchema: z.ZodObject<
  {
    isEnabled: z.ZodDefault<z.ZodBoolean>
    isAuthorized: z.ZodDefault<z.ZodBoolean>
    currentSong: z.ZodOptional<
      z.ZodObject<
        {
          title: z.ZodString
          artist: z.ZodString
          album: z.ZodString
          duration: z.ZodNumber
          playbackTime: z.ZodNumber
        },
        'strip',
        z.ZodTypeAny,
        {
          title: string
          artist: string
          album: string
          duration: number
          playbackTime: number
        },
        {
          title: string
          artist: string
          album: string
          duration: number
          playbackTime: number
        }
      >
    >
    playbackState: z.ZodOptional<z.ZodEnum<['playing', 'paused', 'stopped']>>
  },
  'strip',
  z.ZodTypeAny,
  {
    isEnabled: boolean
    isAuthorized: boolean
    playbackState?: 'playing' | 'paused' | 'stopped' | undefined
    currentSong?:
      | {
          title: string
          artist: string
          album: string
          duration: number
          playbackTime: number
        }
      | undefined
  },
  {
    playbackState?: 'playing' | 'paused' | 'stopped' | undefined
    currentSong?:
      | {
          title: string
          artist: string
          album: string
          duration: number
          playbackTime: number
        }
      | undefined
    isEnabled?: boolean | undefined
    isAuthorized?: boolean | undefined
  }
>
declare class AppleMusicService {
  private currentData
  init(): Promise<void>
  updateFromHost(data: Partial<AppleMusicNowPlaying>): void
  updateConfig(config: Partial<AppleMusicNowPlaying>): void
  getCurrentData(): AppleMusicNowPlaying
}
export declare const appleMusicService: AppleMusicService
export {}
//# sourceMappingURL=apple-music.d.ts.map
