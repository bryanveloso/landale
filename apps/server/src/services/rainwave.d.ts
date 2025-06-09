import { z } from 'zod'
import type { RainwaveNowPlaying } from '@landale/shared'
export declare const RAINWAVE_STATIONS: {
  readonly GAME: 1
  readonly OCREMIX: 2
  readonly COVERS: 3
  readonly CHIPTUNES: 4
  readonly ALL: 5
}
export declare const rainwaveNowPlayingSchema: z.ZodObject<
  {
    stationId: z.ZodDefault<z.ZodNumber>
    stationName: z.ZodOptional<z.ZodString>
    isEnabled: z.ZodDefault<z.ZodBoolean>
    apiKey: z.ZodOptional<z.ZodString>
    userId: z.ZodOptional<z.ZodString>
    currentSong: z.ZodOptional<
      z.ZodObject<
        {
          title: z.ZodString
          artist: z.ZodString
          album: z.ZodString
          length: z.ZodNumber
          startTime: z.ZodNumber
          endTime: z.ZodNumber
          url: z.ZodOptional<z.ZodString>
          albumArt: z.ZodOptional<z.ZodString>
        },
        'strip',
        z.ZodTypeAny,
        {
          length: number
          title: string
          artist: string
          album: string
          startTime: number
          endTime: number
          url?: string | undefined
          albumArt?: string | undefined
        },
        {
          length: number
          title: string
          artist: string
          album: string
          startTime: number
          endTime: number
          url?: string | undefined
          albumArt?: string | undefined
        }
      >
    >
  },
  'strip',
  z.ZodTypeAny,
  {
    isEnabled: boolean
    stationId: number
    currentSong?:
      | {
          length: number
          title: string
          artist: string
          album: string
          startTime: number
          endTime: number
          url?: string | undefined
          albumArt?: string | undefined
        }
      | undefined
    stationName?: string | undefined
    apiKey?: string | undefined
    userId?: string | undefined
  },
  {
    currentSong?:
      | {
          length: number
          title: string
          artist: string
          album: string
          startTime: number
          endTime: number
          url?: string | undefined
          albumArt?: string | undefined
        }
      | undefined
    isEnabled?: boolean | undefined
    stationId?: number | undefined
    stationName?: string | undefined
    apiKey?: string | undefined
    userId?: string | undefined
  }
>
declare class RainwaveService {
  private pollInterval
  private currentData
  init(): Promise<void>
  start(stationId?: number): Promise<void>
  stop(): void
  private fetchNowPlaying
  updateConfig(config: Partial<RainwaveNowPlaying>): void
  getCurrentData(): RainwaveNowPlaying
}
export declare const rainwaveService: RainwaveService
export {}
//# sourceMappingURL=rainwave.d.ts.map
