import { useState, useEffect } from 'react'
import { useMutation } from '@tanstack/react-query'
import { useTRPCClient } from '../lib/trpc'
import { CloudRain, Sparkles, Trash2 } from 'lucide-react'

interface EmoteRainConfig {
  size: number
  lifetime: number
  gravity: number
  restitution: number
  friction: number
  airFriction: number
  spawnDelay: number
  maxEmotes: number
  rotationSpeed: number
}

export function EmoteRainControl() {
  const [isDirty, setIsDirty] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [config, setConfig] = useState<EmoteRainConfig | null>(null)
  const trpcClient = useTRPCClient()
  
  useEffect(() => {
    const subscription = trpcClient.control.config.emoteRain.onConfigUpdate.subscribe(undefined, {
      onData: (data) => {
        setConfig(data)
        setIsLoading(false)
        if (!isDirty) {
          setLocalConfig(data)
        }
      },
      onError: (err) => {
        console.error('Config subscription error:', err)
        setIsLoading(false)
      }
    })
    
    return () => {
      subscription.unsubscribe()
    }
  }, [trpcClient, isDirty])
  
  const updateMutation = useMutation({
    mutationFn: (input: Partial<EmoteRainConfig>) => 
      trpcClient.control.config.emoteRain.update.mutate(input),
    onSuccess: () => {
      setIsDirty(false)
    },
  })
  const burstMutation = useMutation({
    mutationFn: (input: { emoteId?: string; count?: number }) => 
      trpcClient.control.config.emoteRain.burst.mutate(input)
  })
  const clearMutation = useMutation({
    mutationFn: () => trpcClient.control.config.emoteRain.clear.mutate()
  })

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

  const [localConfig, setLocalConfig] = useState<EmoteRainConfig>(defaultConfig)

  const handleChange = (key: keyof typeof localConfig, value: number) => {
    setLocalConfig(prev => ({ ...prev, [key]: value }))
    setIsDirty(true)
  }

  const handleSave = () => {
    updateMutation.mutate(localConfig)
  }

  const handleBurst = () => {
    burstMutation.mutate({ count: 20 })
  }

  const handleClear = () => {
    clearMutation.mutate()
  }

  if (isLoading) {
    return (
      <div className="bg-gray-800 rounded-lg p-6">
        <h2 className="text-xl font-semibold mb-4">Emote Rain Configuration</h2>
        <div className="text-gray-400">Loading...</div>
      </div>
    )
  }

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold flex items-center gap-2">
          <CloudRain className="w-5 h-5" />
          Emote Rain Configuration
        </h2>
        
        <div className="flex gap-2">
          <button
            onClick={handleBurst}
            disabled={burstMutation.isPending}
            className="px-3 py-1.5 bg-purple-600 hover:bg-purple-700 disabled:bg-purple-800 rounded-md text-sm font-medium flex items-center gap-2 transition-colors"
          >
            <Sparkles className="w-4 h-4" />
            Trigger Burst
          </button>
          
          <button
            onClick={handleClear}
            disabled={clearMutation.isPending}
            className="px-3 py-1.5 bg-red-600 hover:bg-red-700 disabled:bg-red-800 rounded-md text-sm font-medium flex items-center gap-2 transition-colors"
          >
            <Trash2 className="w-4 h-4" />
            Clear All
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 mb-6">
        {/* Size */}
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Emote Size
          </label>
          <input
            type="range"
            min="28"
            max="224"
            step="28"
            value={localConfig.size || 112}
            onChange={(e) => handleChange('size', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.size || 112}px</div>
        </div>

        {/* Lifetime */}
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Lifetime
          </label>
          <input
            type="range"
            min="1000"
            max="60000"
            step="1000"
            value={localConfig.lifetime || 30000}
            onChange={(e) => handleChange('lifetime', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{((localConfig.lifetime || 30000) / 1000).toFixed(0)}s</div>
        </div>

        {/* Gravity */}
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Gravity
          </label>
          <input
            type="range"
            min="0.1"
            max="3"
            step="0.1"
            value={localConfig.gravity || 1}
            onChange={(e) => handleChange('gravity', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{(localConfig.gravity || 1).toFixed(1)}</div>
        </div>

        {/* Restitution (Bounciness) */}
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Bounciness
          </label>
          <input
            type="range"
            min="0"
            max="1"
            step="0.1"
            value={localConfig.restitution || 0.4}
            onChange={(e) => handleChange('restitution', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{(localConfig.restitution || 0.4).toFixed(1)}</div>
        </div>

        {/* Max Emotes */}
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Max Emotes
          </label>
          <input
            type="range"
            min="10"
            max="500"
            step="10"
            value={localConfig.maxEmotes || 200}
            onChange={(e) => handleChange('maxEmotes', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.maxEmotes || 200}</div>
        </div>

        {/* Spawn Delay */}
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            Spawn Delay
          </label>
          <input
            type="range"
            min="50"
            max="1000"
            step="50"
            value={localConfig.spawnDelay || 100}
            onChange={(e) => handleChange('spawnDelay', Number(e.target.value))}
            className="w-full"
          />
          <div className="text-sm text-gray-400 mt-1">{localConfig.spawnDelay || 100}ms</div>
        </div>
      </div>

      {isDirty && (
        <div className="flex justify-end">
          <button
            onClick={handleSave}
            disabled={updateMutation.isPending}
            className="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-800 rounded-md font-medium transition-colors"
          >
            {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
          </button>
        </div>
      )}
    </div>
  )
}