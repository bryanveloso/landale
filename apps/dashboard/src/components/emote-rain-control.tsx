import { useState } from 'react'
import { CloudRain, Sparkles, Trash2, Wifi, WifiOff } from 'lucide-react'
import { useSubscription } from '@/hooks/use-subscription'
import { useSubscriptionAction } from '@/hooks/use-subscription-action'
import type { EmoteRainConfig } from '@/types'

export function EmoteRainControl() {
  const [isDirty, setIsDirty] = useState(false)

  const {
    data: config,
    isConnected,
    isError
  } = useSubscription<EmoteRainConfig>('control.config.emoteRain.onConfigUpdate')

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

  const [localConfig, setLocalConfig] = useState<EmoteRainConfig>(config || defaultConfig)

  // Update local config when server config changes (but not if we have local changes)
  if (config && !isDirty && JSON.stringify(config) !== JSON.stringify(localConfig)) {
    setLocalConfig(config)
  }

  const handleChange = (key: keyof EmoteRainConfig, value: number) => {
    setLocalConfig((prev) => ({ ...prev, [key]: value }))
    setIsDirty(true)
  }

  const { execute: updateConfig } = useSubscriptionAction<EmoteRainConfig, EmoteRainConfig>(
    'control.config.emoteRain.update'
  )

  const handleSave = async () => {
    try {
      await updateConfig(localConfig)
      setIsDirty(false)
    } catch (error) {
      console.error('Failed to save config:', error)
    }
  }

  const { execute: triggerBurst } = useSubscriptionAction<{ count: number }, { success: boolean }>(
    'control.config.emoteRain.burst'
  )

  const handleBurst = async () => {
    try {
      await triggerBurst({ count: 20 })
    } catch (error) {
      console.error('Failed to trigger burst:', error)
    }
  }

  const { execute: clearEmotes } = useSubscriptionAction<undefined, { success: boolean }>(
    'control.config.emoteRain.clear'
  )

  const handleClear = async () => {
    try {
      await clearEmotes()
    } catch (error) {
      console.error('Failed to clear emotes:', error)
    }
  }

  const getConnectionIndicator = () => {
    if (isError) return <WifiOff className="h-4 w-4 text-red-500" />
    if (isConnected) return <Wifi className="h-4 w-4 text-green-500" />
    return <div className="h-4 w-4 animate-pulse rounded-full bg-gray-500" />
  }

  return (
    <div className="rounded-lg bg-gray-800 p-6">
      <div className="mb-6 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h2 className="flex items-center gap-2 text-xl font-semibold">
            <CloudRain className="h-5 w-5" />
            Emote Rain Configuration
          </h2>
          {getConnectionIndicator()}
        </div>

        <div className="flex gap-2">
          <button
            onClick={handleBurst}
            disabled={!isConnected}
            className="flex items-center gap-2 rounded-md bg-purple-600 px-3 py-1.5 text-sm font-medium transition-colors hover:bg-purple-700 disabled:bg-purple-800 disabled:opacity-50">
            <Sparkles className="h-4 w-4" />
            Trigger Burst
          </button>

          <button
            onClick={handleClear}
            disabled={!isConnected}
            className="flex items-center gap-2 rounded-md bg-red-600 px-3 py-1.5 text-sm font-medium transition-colors hover:bg-red-700 disabled:bg-red-800 disabled:opacity-50">
            <Trash2 className="h-4 w-4" />
            Clear All
          </button>
        </div>
      </div>

      {isError && (
        <div className="mb-4 text-sm text-red-400">
          Unable to connect to server. Configuration changes will not be saved.
        </div>
      )}

      <div className="mb-6 grid grid-cols-2 gap-4">
        <div>
          <label className="mb-2 block text-sm font-medium text-gray-300">Emote Size</label>
          <input
            type="range"
            min="28"
            max="224"
            step="28"
            value={localConfig.size}
            onChange={(e) => {
              handleChange('size', Number(e.target.value))
            }}
            className="w-full"
          />
          <div className="mt-1 text-sm text-gray-400">{localConfig.size}px</div>
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-300">Lifetime</label>
          <input
            type="range"
            min="1000"
            max="60000"
            step="1000"
            value={localConfig.lifetime}
            onChange={(e) => {
              handleChange('lifetime', Number(e.target.value))
            }}
            className="w-full"
          />
          <div className="mt-1 text-sm text-gray-400">{(localConfig.lifetime / 1000).toFixed(0)}s</div>
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-300">Gravity</label>
          <input
            type="range"
            min="0.1"
            max="3"
            step="0.1"
            value={localConfig.gravity}
            onChange={(e) => {
              handleChange('gravity', Number(e.target.value))
            }}
            className="w-full"
          />
          <div className="mt-1 text-sm text-gray-400">{localConfig.gravity.toFixed(1)}</div>
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-300">Bounciness</label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={localConfig.restitution}
            onChange={(e) => {
              handleChange('restitution', Number(e.target.value))
            }}
            className="w-full"
          />
          <div className="mt-1 text-sm text-gray-400">{localConfig.restitution.toFixed(1)}</div>
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-300">Max Emotes</label>
          <input
            type="range"
            min="10"
            max="500"
            step="10"
            value={localConfig.maxEmotes}
            onChange={(e) => {
              handleChange('maxEmotes', Number(e.target.value))
            }}
            className="w-full"
          />
          <div className="mt-1 text-sm text-gray-400">{localConfig.maxEmotes}</div>
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-300">Spawn Delay</label>
          <input
            type="range"
            min="50"
            max="1000"
            step="50"
            value={localConfig.spawnDelay}
            onChange={(e) => {
              handleChange('spawnDelay', Number(e.target.value))
            }}
            className="w-full"
          />
          <div className="mt-1 text-sm text-gray-400">{localConfig.spawnDelay}ms</div>
        </div>
      </div>

      {isDirty && (
        <div className="flex justify-end">
          <button
            onClick={handleSave}
            disabled={!isConnected}
            className="rounded-md bg-blue-600 px-4 py-2 font-medium transition-colors hover:bg-blue-700 disabled:bg-blue-800 disabled:opacity-50">
            Save Changes
          </button>
        </div>
      )}
    </div>
  )
}
