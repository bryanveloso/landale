import { useDisplay } from '@/hooks/use-display'
import type { AppleMusicNowPlaying } from '@landale/shared'
import { Music, Wifi, WifiOff } from 'lucide-react'

export function AppleMusicControl() {
  const { data, display, isConnected, update, setVisibility } = useDisplay<AppleMusicNowPlaying>('appleMusic')

  const handleToggle = () => {
    update({ isEnabled: !data?.isEnabled })
  }

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <Music className="h-5 w-5 text-pink-500" />
          <h3 className="text-lg font-medium text-gray-100">Apple Music Now Playing</h3>
        </div>
        <div className="flex items-center gap-2">
          {isConnected ? (
            <Wifi className="h-4 w-4 text-green-500" />
          ) : (
            <WifiOff className="h-4 w-4 text-red-500" />
          )}
          <span className="text-xs text-gray-400">
            {isConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>
      </div>

      <div className="space-y-4">
        {/* Enable/Disable toggle */}
        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-300">Enable Apple Music</span>
          <button
            onClick={handleToggle}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              data?.isEnabled ? 'bg-pink-600' : 'bg-gray-600'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                data?.isEnabled ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        {/* Visibility toggle */}
        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-300">Show Overlay</span>
          <button
            onClick={() => setVisibility(!display?.isVisible)}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              display?.isVisible ? 'bg-pink-600' : 'bg-gray-600'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                display?.isVisible ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        {/* Current song info */}
        {data?.currentSong && data.isEnabled && (
          <div className="bg-gray-700/50 rounded-md p-3 space-y-1">
            <div className="text-sm text-gray-100 font-medium truncate">
              {data.currentSong.title}
            </div>
            <div className="text-xs text-gray-400 truncate">
              {data.currentSong.artist} • {data.currentSong.album}
            </div>
            <div className="text-xs text-gray-500">
              {data.playbackState === 'playing' ? '▶️ Playing' : 
               data.playbackState === 'paused' ? '⏸️ Paused' : '⏹️ Stopped'}
            </div>
          </div>
        )}

        {/* Host service info */}
        {!data?.currentSong && data?.isEnabled && (
          <div className="bg-gray-700/30 rounded-md p-3 text-xs text-gray-400 space-y-2">
            <p className="font-medium">Host Service Required:</p>
            <p>The Apple Music monitor service must be running on your Mac Mini host.</p>
            <p>Start it with: <code className="bg-gray-900 px-1 rounded">node /path/to/apple-music-monitor.js</code></p>
          </div>
        )}
      </div>
    </div>
  )
}