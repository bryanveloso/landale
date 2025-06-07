export interface RainwaveNowPlaying {
  stationId: number
  stationName?: string
  isEnabled: boolean
  apiKey?: string
  userId?: string
  currentSong?: {
    title: string
    artist: string
    album: string
    length: number // in seconds
    startTime: number // unix timestamp
    endTime: number // unix timestamp
    url?: string
    albumArt?: string
  }
}