import { useEffect, useState } from 'react'
import { useDisplay } from '@/hooks/use-display'
import type { RainwaveNowPlaying, AppleMusicNowPlaying } from '@landale/shared'

type MusicService = 'rainwave' | 'appleMusic'

interface MusicData {
  service: MusicService
  isEnabled: boolean
  currentSong?: {
    title: string
    artist: string
    album: string
    albumArt?: string
  }
  stationName?: string
  playbackState?: 'playing' | 'paused' | 'stopped'
  progress: number
  timeElapsed: string
  timeRemaining?: string
  timeTotal?: string
}

// Unified music widget
function MusicWidget({ service }: { service: MusicService }) {
  const rainwave = useDisplay<RainwaveNowPlaying>('rainwave')
  const appleMusic = useDisplay<AppleMusicNowPlaying>('appleMusic')

  const { data, isConnected, isVisible } = service === 'rainwave' ? rainwave : appleMusic

  const [musicData, setMusicData] = useState<MusicData>({
    service,
    isEnabled: false,
    progress: 0,
    timeElapsed: '0:00'
  })

  // Helper to format seconds to mm:ss
  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins.toString()}:${secs.toString().padStart(2, '0')}`
  }

  useEffect(() => {
    if (!data || !data.isEnabled) {
      setMusicData((prev) => ({ ...prev, isEnabled: false, progress: 0 }))
      return
    }

    const updateProgress = () => {
      if (service === 'rainwave' && 'currentSong' in data && data.currentSong) {
        const rainwaveData = data as RainwaveNowPlaying
        if (!rainwaveData.currentSong) return
        const now = Date.now() / 1000
        const duration = rainwaveData.currentSong.endTime - rainwaveData.currentSong.startTime
        const elapsed = now - rainwaveData.currentSong.startTime
        const remaining = rainwaveData.currentSong.endTime - now
        const percentage = Math.min(100, Math.max(0, (elapsed / duration) * 100))

        setMusicData({
          service,
          isEnabled: true,
          currentSong: {
            title: rainwaveData.currentSong.title,
            artist: rainwaveData.currentSong.artist,
            album: rainwaveData.currentSong.album,
            albumArt: rainwaveData.currentSong.albumArt
          },
          stationName: rainwaveData.stationName,
          playbackState: 'playing',
          progress: percentage,
          timeElapsed: formatTime(Math.max(0, elapsed)),
          timeRemaining: formatTime(Math.max(0, remaining))
        })
      } else if (service === 'appleMusic' && 'currentSong' in data && data.currentSong) {
        const appleData = data as AppleMusicNowPlaying
        if (!appleData.currentSong) return
        const { playbackTime, duration } = appleData.currentSong
        const percentage = Math.min(100, Math.max(0, (playbackTime / duration) * 100))

        setMusicData({
          service,
          isEnabled: true,
          currentSong: {
            title: appleData.currentSong.title,
            artist: appleData.currentSong.artist,
            album: appleData.currentSong.album
          },
          playbackState: appleData.playbackState,
          progress: percentage,
          timeElapsed: formatTime(playbackTime),
          timeTotal: formatTime(duration)
        })
      }
    }

    // Initial update
    updateProgress()

    // Update every second
    const interval = setInterval(updateProgress, 1000)
    return () => {
      clearInterval(interval)
    }
  }, [data, service])

  if (!isVisible || !musicData.isEnabled || !musicData.currentSong) {
    return null
  }

  // Position based on service
  const positionClass = service === 'rainwave' ? 'bottom-4 right-4' : 'bottom-4 left-4'

  return (
    <div
      className={`fixed ${positionClass} min-w-[320px] rounded-lg border border-gray-700/50 bg-gray-900/90 p-4 shadow-xl backdrop-blur-sm`}>
      {/* Connection indicator */}
      <div className="absolute top-2 right-2">
        <div className={`h-2 w-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
      </div>

      {/* Album art and info */}
      <div className="flex items-start gap-4">
        {musicData.currentSong.albumArt && (
          <img
            src={musicData.currentSong.albumArt}
            alt={musicData.currentSong.album}
            className="h-16 w-16 rounded-md shadow-md"
          />
        )}

        <div className="min-w-0 flex-1">
          {/* Service/Station name */}
          <div className="mb-1 text-xs tracking-wider text-gray-400 uppercase">
            {service === 'rainwave' ? musicData.stationName || 'Rainwave' : 'Apple Music'}
          </div>

          {/* Song title */}
          <div className="truncate font-medium text-white">{musicData.currentSong.title}</div>

          {/* Artist */}
          <div className="truncate text-sm text-gray-300">{musicData.currentSong.artist}</div>

          {/* Album */}
          <div className="mt-1 truncate text-xs text-gray-400">{musicData.currentSong.album}</div>
        </div>
      </div>

      {/* Progress bar and time */}
      <div className="mt-3 space-y-1">
        <div className="h-1 overflow-hidden rounded-full bg-gray-700">
          <div
            className={`h-full bg-gradient-to-r ${
              service === 'rainwave' ? 'from-blue-500 to-purple-500' : 'from-pink-500 to-purple-500'
            }`}
            style={{ width: `${musicData.progress.toString()}%` }}
          />
        </div>
        <div className="flex justify-between text-xs text-gray-400">
          <span>{musicData.timeElapsed}</span>
          <span>{musicData.timeRemaining ? `-${musicData.timeRemaining}` : musicData.timeTotal}</span>
        </div>
      </div>
    </div>
  )
}

// Main component that shows both
export function NowPlaying() {
  return (
    <>
      <MusicWidget service="rainwave" />
      <MusicWidget service="appleMusic" />
    </>
  )
}
