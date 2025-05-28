import { useState } from 'react'
import { CloudRain, Sparkles, Trash2, Wifi, WifiOff } from 'lucide-react'
import { useSubscription } from '@/hooks/use-subscription'
import { trpc } from '@/lib/trpc'
import type { EmoteRainConfig } from '@/types'

export function EmoteRainControl() {
  const [isDirty, setIsDirty] = useState(false)
  
  const { data: config, isConnected, isError } = useSubscription<EmoteRainConfig>(
    'control.config.emoteRain.onConfigUpdate'
  )

  const defaultConfig: EmoteRainConfig = {
    size: 112,
    lifetime: 30000,
    gravity: 1,
    restitution: 0.4,
    friction: 0.3,
    airFriction: 0.001,
    spawnDelay: 100,
    maxEmotes: 200,
    rotationSpeed: 0.2
  }

  const [localConfig, setLocalConfig] = useState<EmoteRainConfig>(
    config || defaultConfig
  )

  // Update local config when server config changes (but not if we have local changes)
  if (config && !isDirty && JSON.stringify(config) !== JSON.stringify(localConfig)) {
    setLocalConfig(config)
  }

  const handleChange = (key: keyof EmoteRainConfig, value: number) => {
    setLocalConfig(prev => ({ ...prev, [key]: value }))
    setIsDirty(true)
  }

  const handleSave = async () => {
    try {
      await trpc.control.config.emoteRain.update.mutate(localConfig)
      setIsDirty(false)
    } catch (error) {
      console.error('Failed to save config:', error)
    }
  }

  const handleBurst = async () => {
    try {
      await trpc.control.config.emoteRain.burst.mutate({ count: 20 })
    } catch (error) {
      console.error('Failed to trigger burst:', error)
    }
  }

  const handleClear = async () => {
    try {
      await trpc.control.config.emoteRain.clear.mutate()
    } catch (error) {
      console.error('Failed to clear emotes:', error)
    }
  }

  const getConnectionIndicator = () => {
    if (isError) return <WifiOff className="w-4 h-4 text-red-500" />
    if (isConnected) return <Wifi className="w-4 h-4 text-green-500" />
    return <div className="w-4 h-4 bg-gray-500 rounded-full animate-pulse" />
  }

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-2">
          <h2 className="text-xl font-semibold flex items-center gap-2">
            <CloudRain className="w-5 h-5" />
            Emote Rain Configuration
          </h2>
          {getConnectionIndicator()}
        </div>
        
        <div className="flex gap-2">
          <button
            onClick={handleBurst}
            disabled={!isConnected}
            className="px-3 py-1.5 bg-purple-600 hover:bg-purple-700 disabled:bg-purple-800 disabled:opacity-50 rounded-md text-sm font-medium flex items-center gap-2 transition-colors"
          >
            <Sparkles className="w-4 h-4" />
            Trigger Burst
          </button>
          
          <button
            onClick={handleClear}
            disabled={!isConnected}
            className="px-3 py-1.5 bg-red-600 hover:bg-red-700 disabled:bg-red-800 disabled:opacity-50 rounded-md text-sm font-medium flex items-center gap-2 transition-colors"
          >
            <Trash2 className="w-4 h-4" />
            Clear All
          </button>
        </div>
      </div>

      {isError && (
        <div className="text-red-400 text-sm mb-4">
          Unable to connect to server. Configuration changes will not be saved.
        </div>
      )}

      <div className="grid grid-cols-2 gap-4 mb-6">
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Emote Size
          </label>
          <input
            type="range"
            min="28"
            max="224"
            step="28"
            value={localConfig.size}
            onChange={(e) => handleChange('size', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.size}px</div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Lifetime
          </label>
          <input
            type="range"
            min="1000"
            max="60000"
            step="1000"
            value={localConfig.lifetime}
            onChange={(e) => handleChange('lifetime', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{(localConfig.lifetime / 1000).toFixed(0)}s</div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Gravity
          </label>
          <input
            type="range"
            min="0.1"
            max="3"
            step="0.1"
            value={localConfig.gravity}
            onChange={(e) => handleChange('gravity', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.gravity.toFixed(1)}</div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Bounciness
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={localConfig.restitution}
            onChange={(e) => handleChange('restitution', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.restitution.toFixed(1)}</div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Max Emotes
          </label>
          <input
            type="range"
            min="10"
            max="500"
            step="10"
            value={localConfig.maxEmotes}
            onChange={(e) => handleChange('maxEmotes', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.maxEmotes}</div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Spawn Delay
          </label>
          <input
            type="range"
            min="50"
            max="1000"
            step="50"
            value={localConfig.spawnDelay}
            onChange={(e) => handleChange('spawnDelay', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.spawnDelay}ms</div>
        </div>
      </div>

      {isDirty && (
        <div className="flex justify-end">
          <button
            onClick={handleSave}
            disabled={!isConnected}
            className="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-800 disabled:opacity-50 rounded-md font-medium transition-colors"
          >
            Save Changes
          </button>
        </div>
      )}
    </div>
  )
}