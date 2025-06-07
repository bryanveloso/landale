import { useDisplay } from '@/hooks/use-display'
import type { RainwaveNowPlaying } from '@landale/shared'
import { Music, Wifi, WifiOff } from 'lucide-react'

const STATIONS = [
  { id: 1, name: 'Game' },
  { id: 2, name: 'OC ReMix' },
  { id: 3, name: 'Covers' },
  { id: 4, name: 'Chiptunes' },
  { id: 5, name: 'All' }
]

export function RainwaveControl() {
  const { data, display, isConnected, update, setVisibility } = useDisplay<RainwaveNowPlaying>('rainwave')

  const handleToggle = () => {
    update({ isEnabled: !data?.isEnabled })
  }

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <Music className="h-5 w-5 text-purple-500" />
          <h3 className="text-lg font-medium text-gray-100">Rainwave Now Playing</h3>
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
          <span className="text-sm text-gray-300">Enable Rainwave</span>
          <button
            onClick={handleToggle}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              data?.isEnabled ? 'bg-purple-600' : 'bg-gray-600'
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
              display?.isVisible ? 'bg-purple-600' : 'bg-gray-600'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                display?.isVisible ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        {/* Current station display */}
        <div>
          <label className="block text-sm text-gray-300 mb-2">Current Station</label>
          <div className="bg-gray-700 text-gray-100 px-3 py-2 rounded-md border border-gray-600">
            {data?.stationName || STATIONS.find(s => s.id === data?.stationId)?.name || 'Not listening'}
          </div>
          <p className="text-xs text-gray-500 mt-1">
            Automatically detects which station you're listening to
          </p>
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
          </div>
        )}

        {/* API credentials info */}
        <div className="bg-gray-700/30 rounded-md p-3 text-xs text-gray-400">
          <p>
            API Key: {data?.apiKey ? '••••••••' + data.apiKey.slice(-2) : 'Not configured'}
          </p>
          <p>
            User ID: {data?.userId || 'Not configured'}
          </p>
          <p className="mt-1 text-gray-500">
            Widget only appears when you're actively listening
          </p>
        </div>
      </div>
    </div>
  )
}