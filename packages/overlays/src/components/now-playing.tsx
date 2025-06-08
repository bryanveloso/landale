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
    return `${mins}:${secs.toString().padStart(2, '0')}`
  }

  useEffect(() => {
    if (!data || !data.isEnabled) {
      setMusicData(prev => ({ ...prev, isEnabled: false, progress: 0 }))
      return
    }

    const updateProgress = () => {
      if (service === 'rainwave' && 'currentSong' in data && data.currentSong) {
        const now = Date.now() / 1000
        const duration = data.currentSong.endTime - data.currentSong.startTime
        const elapsed = now - data.currentSong.startTime
        const remaining = data.currentSong.endTime - now
        const percentage = Math.min(100, Math.max(0, (elapsed / duration) * 100))
        
        setMusicData({
          service,
          isEnabled: true,
          currentSong: {
            title: data.currentSong.title,
            artist: data.currentSong.artist,
            album: data.currentSong.album,
            albumArt: data.currentSong.albumArt
          },
          stationName: (data as RainwaveNowPlaying).stationName,
          playbackState: 'playing',
          progress: percentage,
          timeElapsed: formatTime(Math.max(0, elapsed)),
          timeRemaining: formatTime(Math.max(0, remaining))
        })
      } else if (service === 'appleMusic' && 'currentSong' in data && data.currentSong) {
        const { playbackTime, duration } = data.currentSong
        const percentage = Math.min(100, Math.max(0, (playbackTime / duration) * 100))
        
        setMusicData({
          service,
          isEnabled: true,
          currentSong: {
            title: data.currentSong.title,
            artist: data.currentSong.artist,
            album: data.currentSong.album
          },
          playbackState: data.playbackState,
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
    return () => clearInterval(interval)
  }, [data, service])

  if (!isVisible || !musicData.isEnabled || !musicData.currentSong) {
    return null
  }

  // Position based on service
  const positionClass = service === 'rainwave' ? 'bottom-4 right-4' : 'bottom-4 left-4'
  
  return (
    <div className={`fixed ${positionClass} bg-gray-900/90 backdrop-blur-sm rounded-lg shadow-xl p-4 min-w-[320px] border border-gray-700/50`}>
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
            className="w-16 h-16 rounded-md shadow-md"
          />
        )}
        
        <div className="flex-1 min-w-0">
          {/* Service/Station name */}
          <div className="text-xs text-gray-400 uppercase tracking-wider mb-1">
            {service === 'rainwave' ? musicData.stationName || 'Rainwave' : 'Apple Music'}
          </div>
          
          {/* Song title */}
          <div className="text-white font-medium truncate">
            {musicData.currentSong.title}
          </div>
          
          {/* Artist */}
          <div className="text-sm text-gray-300 truncate">
            {musicData.currentSong.artist}
          </div>
          
          {/* Album */}
          <div className="text-xs text-gray-400 truncate mt-1">
            {musicData.currentSong.album}
          </div>
        </div>
      </div>

      {/* Progress bar and time */}
      <div className="mt-3 space-y-1">
        <div className="h-1 bg-gray-700 rounded-full overflow-hidden">
          <div
            className={`h-full bg-gradient-to-r ${
              service === 'rainwave' 
                ? 'from-blue-500 to-purple-500' 
                : 'from-pink-500 to-purple-500'
            }`}
            style={{ width: `${musicData.progress}%` }}
          />
        </div>
        <div className="flex justify-between text-xs text-gray-400">
          <span>{musicData.timeElapsed}</span>
          <span>
            {musicData.timeRemaining ? `-${musicData.timeRemaining}` : musicData.timeTotal}
          </span>
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