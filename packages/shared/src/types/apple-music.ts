export interface AppleMusicNowPlaying {
  isEnabled: boolean
  isAuthorized: boolean // Always true with host service
  currentSong?: {
    title: string
    artist: string
    album: string
    duration: number // in seconds
    playbackTime: number // current position in seconds
  }
  playbackState?: 'playing' | 'paused' | 'stopped'
}