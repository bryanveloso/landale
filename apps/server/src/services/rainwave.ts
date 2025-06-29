import { z } from 'zod'
import { createLogger } from '@landale/logger'
import { displayManager } from '@/services/display-manager'
import type { RainwaveNowPlaying } from '@landale/shared'

interface RainwaveArtist {
  name: string
}

interface RainwaveAlbum {
  name: string
  art?: string
}

interface RainwaveSong {
  title: string
  artists?: RainwaveArtist[]
  albums?: RainwaveAlbum[]
  length: number
  url?: string
}

interface RainwaveApiResponse {
  user?: {
    id?: number | string
  }
  station_name?: string
  sched_current?: {
    songs?: RainwaveSong[]
    start_actual?: number
    start?: number
    end?: number
  }
}

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'rainwave' })

// Rainwave station IDs
export const RAINWAVE_STATIONS = {
  GAME: 1,
  OCREMIX: 2,
  COVERS: 3,
  CHIPTUNES: 4,
  ALL: 5
} as const

// Schema for Rainwave now playing data
export const rainwaveNowPlayingSchema = z.object({
  stationId: z.number().default(RAINWAVE_STATIONS.COVERS),
  stationName: z.string().optional(),
  isEnabled: z.boolean().default(true),
  apiKey: z.string().optional(),
  userId: z.string().optional(),
  currentSong: z
    .object({
      title: z.string(),
      artist: z.string(),
      album: z.string(),
      length: z.number(), // in seconds
      startTime: z.number(), // unix timestamp
      endTime: z.number(), // unix timestamp
      url: z.string().optional(),
      albumArt: z.string().optional()
    })
    .optional()
})

class RainwaveService {
  private pollInterval: Timer | null = null
  private currentData: RainwaveNowPlaying = {
    stationId: RAINWAVE_STATIONS.COVERS,
    isEnabled: false
  }

  init() {
    log.info('Initializing Rainwave service')
  }

  async start(stationId: number = RAINWAVE_STATIONS.COVERS) {
    if (this.pollInterval) {
      this.stop()
    }

    this.currentData.stationId = stationId
    this.currentData.isEnabled = true

    // Initial fetch
    await this.fetchNowPlaying()

    // Poll every 10 seconds
    this.pollInterval = setInterval(() => {
      void this.fetchNowPlaying()
    }, 10000)

    log.info('Started Rainwave polling', { metadata: { stationId } })
  }

  stop() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }

    this.currentData.isEnabled = false
    this.currentData.currentSong = undefined
    displayManager.update('rainwave', this.currentData)

    log.info('Stopped Rainwave polling')
  }

  private async fetchNowPlaying() {
    try {
      // Check all stations to find where the user is listening
      const stations = [1, 2, 3, 4, 5] // All station IDs
      let activeStation: number | null = null
      let activeData: RainwaveApiResponse | null = null

      for (const stationId of stations) {
        const formData = new URLSearchParams()
        formData.append('sid', stationId.toString())

        // Add auth if available
        if (this.currentData.apiKey && this.currentData.userId) {
          formData.append('key', this.currentData.apiKey)
          formData.append('user_id', this.currentData.userId)
        }

        const response = await fetch('https://rainwave.cc/api4/info', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
          },
          body: formData.toString()
        })

        if (!response.ok) {
          continue
        }

        const data = (await response.json()) as RainwaveApiResponse

        // Check if user is listening to this station
        if (data.user?.id && String(data.user.id) === this.currentData.userId) {
          activeStation = stationId
          activeData = data
          break
        }
      }

      // If user is not listening to any station, clear the current song
      if (!activeStation || !activeData) {
        this.currentData.currentSong = undefined
        log.debug('User is not currently listening to Rainwave')
        displayManager.update('rainwave', this.currentData)
        return
      }

      // Update the station if it changed
      if (activeStation !== this.currentData.stationId) {
        this.currentData.stationId = activeStation
        log.info('User switched station', { metadata: { stationId: activeStation } })
      }

      const data = activeData

      // Check if the user is currently listening
      // The user object should only exist if authenticated and listening
      const isListening = !!(data.user?.id && String(data.user.id) === this.currentData.userId)

      if (isListening) {
        // Extract current song info from the response
        const sched = data.sched_current
        if (sched?.songs && sched.songs.length > 0) {
          const song = sched.songs[0]

          this.currentData.currentSong = song && {
            title: song.title,
            artist: song.artists ? song.artists.map((a) => a.name).join(', ') : 'Unknown',
            album: song.albums?.[0]?.name ?? 'Unknown',
            length: song.length || 0,
            startTime: sched.start_actual || sched.start || Date.now() / 1000,
            endTime: sched.end || (sched.start ?? 0) + song.length || Date.now() / 1000 + (song.length || 0),
            url: song.url,
            albumArt: song.albums?.[0]?.art ? `https://rainwave.cc${song.albums[0].art}_320.jpg` : undefined
          }
        }

        // Get station name
        if (data.station_name) {
          this.currentData.stationName = data.station_name
        }
      } else {
        // User is not listening, clear the current song
        this.currentData.currentSong = undefined
        log.debug('User is not currently listening to Rainwave')
      }

      // Update display manager directly
      displayManager.update('rainwave', this.currentData)
    } catch (error) {
      log.error('Failed to fetch Rainwave data', { error: error as Error })
    }
  }

  updateConfig(config: Partial<RainwaveNowPlaying>) {
    const wasEnabled = this.currentData.isEnabled

    this.currentData = {
      ...this.currentData,
      ...config
    }

    // Handle enable/disable
    if (config.isEnabled !== undefined && config.isEnabled !== wasEnabled) {
      if (config.isEnabled) {
        void this.start(this.currentData.stationId)
      } else {
        this.stop()
      }
    }

    // Handle station change
    if (config.stationId && config.stationId !== this.currentData.stationId && this.currentData.isEnabled) {
      void this.start(config.stationId)
    }

    // Don't emit rainwave:update here to prevent circular updates
    // The update will be emitted by fetchNowPlaying() when data changes
  }

  getCurrentData(): RainwaveNowPlaying {
    return this.currentData
  }
}

export const rainwaveService = new RainwaveService()

// Export getter for health checks
export function getRainwaveService(): RainwaveService {
  return rainwaveService
}
