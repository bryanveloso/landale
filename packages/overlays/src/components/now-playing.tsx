import { useEffect, useState } from 'react'
import { useDisplay } from '@/hooks/use-display'
import type { RainwaveNowPlaying } from '@landale/shared'

export function NowPlaying() {
  const { data, isConnected, isVisible } = useDisplay<RainwaveNowPlaying>('rainwave')
  const [progress, setProgress] = useState(0)
  const [timeRemaining, setTimeRemaining] = useState<string>('')
  const [timeElapsed, setTimeElapsed] = useState<string>('')

  // Helper to format seconds to mm:ss
  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
  }

  useEffect(() => {
    if (!data?.currentSong || !data.isEnabled) {
      setProgress(0)
      return
    }

    const updateProgress = () => {
      const now = Date.now() / 1000
      const duration = data.currentSong!.endTime - data.currentSong!.startTime
      const elapsed = now - data.currentSong!.startTime
      const remaining = data.currentSong!.endTime - now
      
      const percentage = Math.min(100, Math.max(0, (elapsed / duration) * 100))
      
      
      setProgress(percentage)
      
      // Update time displays
      setTimeElapsed(formatTime(Math.max(0, elapsed)))
      setTimeRemaining(formatTime(Math.max(0, remaining)))
    }

    // Initial update
    updateProgress()

    // Update every second
    const interval = setInterval(updateProgress, 1000)
    return () => clearInterval(interval)
  }, [data])

  if (!isVisible || !data?.isEnabled || !data?.currentSong) {
    return null
  }

  return (
    <div className="fixed bottom-4 right-4 bg-gray-900/90 backdrop-blur-sm rounded-lg shadow-xl p-4 min-w-[320px] border border-gray-700/50">
      {/* Connection indicator */}
      <div className="absolute top-2 right-2">
        <div className={`h-2 w-2 rounded-full ${isConnected ? 'bg-green-500' : 'bg-red-500'}`} />
      </div>

      {/* Album art and info */}
      <div className="flex items-start gap-4">
        {data.currentSong.albumArt && (
          <img
            src={data.currentSong.albumArt}
            alt={data.currentSong.album}
            className="w-16 h-16 rounded-md shadow-md"
          />
        )}
        
        <div className="flex-1 min-w-0">
          {/* Station name */}
          {data.stationName && (
            <div className="text-xs text-gray-400 uppercase tracking-wider mb-1">
              {data.stationName}
            </div>
          )}
          
          {/* Song title */}
          <div className="text-white font-medium truncate">
            {data.currentSong.title}
          </div>
          
          {/* Artist */}
          <div className="text-sm text-gray-300 truncate">
            {data.currentSong.artist}
          </div>
          
          {/* Album */}
          <div className="text-xs text-gray-400 truncate mt-1">
            {data.currentSong.album}
          </div>
        </div>
      </div>

      {/* Progress bar and time */}
      <div className="mt-3 space-y-1">
        <div className="h-1 bg-gray-700 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-blue-500 to-purple-500"
            style={{ width: `${progress}%` }}
          />
        </div>
        <div className="flex justify-between text-xs text-gray-400">
          <span>{timeElapsed}</span>
          <span>-{timeRemaining}</span>
        </div>
      </div>
    </div>
  )
}