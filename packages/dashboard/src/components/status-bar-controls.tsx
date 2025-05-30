import { useState } from 'react'
import { useSubscription } from '@/hooks/use-subscription'
import { trpcClient } from '@/lib/trpc-client'
import type { StatusBarMode, StatusBarState, StatusBarConfig } from '@landale/server'
import { Wifi, WifiOff, Eye, EyeOff } from 'lucide-react'

const modeOptions: { value: StatusBarMode; label: string }[] = [
  { value: 'preshow', label: 'Pre-Show' },
  { value: 'soapbox', label: 'Soapbox' },
  { value: 'game', label: 'Gaming' },
  { value: 'outro', label: 'Outro' },
  { value: 'break', label: 'On Break' },
  { value: 'custom', label: 'Custom' }
]

export function StatusBarControls() {
  const { data: state, isConnected } = useSubscription<StatusBarState>('control.statusBar.onUpdate')
  const [customText, setCustomText] = useState('')

  const handleModeChange = async (mode: StatusBarMode) => {
    try {
      await trpcClient.control.statusBar.setMode.mutate({ mode })
    } catch (error) {
      console.error('Failed to update mode:', error)
    }
  }

  const handleVisibilityToggle = async () => {
    try {
      await trpcClient.control.statusBar.setVisibility.mutate({ isVisible: !state?.isVisible })
    } catch (error) {
      console.error('Failed to toggle visibility:', error)
    }
  }

  const handleCustomTextSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    try {
      await trpcClient.control.statusBar.update.mutate({ 
        mode: 'custom',
        text: customText 
      })
      setCustomText('')
    } catch (error) {
      console.error('Failed to set custom text:', error)
    }
  }

  const handlePositionChange = async (position: 'top' | 'bottom') => {
    try {
      await trpcClient.control.statusBar.update.mutate({ position })
    } catch (error) {
      console.error('Failed to update position:', error)
    }
  }

  return (
    <div className="rounded-lg border border-gray-700 bg-gray-800 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-lg font-semibold text-gray-100">Status Bar</h3>
        <div className="flex items-center gap-2">
          {isConnected ? (
            <Wifi className="h-4 w-4 text-green-500" />
          ) : (
            <WifiOff className="h-4 w-4 text-red-500" />
          )}
        </div>
      </div>

      <div className="space-y-6">
        {/* Visibility Toggle */}
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-gray-100">Show Status Bar</span>
          <button
            onClick={handleVisibilityToggle}
            className={`flex h-10 w-10 items-center justify-center rounded-lg transition-colors ${
              state?.isVisible 
                ? 'bg-green-600 text-white hover:bg-green-700' 
                : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
            }`}
          >
            {state?.isVisible ? <Eye className="h-5 w-5" /> : <EyeOff className="h-5 w-5" />}
          </button>
        </div>

        {/* Position */}
        <div className="space-y-2">
          <span className="text-sm font-medium text-gray-100">Position</span>
          <div className="flex gap-2">
            <button
              onClick={() => handlePositionChange('top')}
              className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                state?.position === 'top'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              Top
            </button>
            <button
              onClick={() => handlePositionChange('bottom')}
              className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                state?.position === 'bottom'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              Bottom
            </button>
          </div>
        </div>

        {/* Mode Selection */}
        <div className="space-y-2">
          <span className="text-sm font-medium text-gray-100">Mode</span>
          <div className="grid grid-cols-2 gap-2">
            {modeOptions.map((option) => (
              <button
                key={option.value}
                onClick={() => handleModeChange(option.value)}
                className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                  state?.mode === option.value
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>

        {/* Custom Text */}
        <form onSubmit={handleCustomTextSubmit} className="space-y-2">
          <label htmlFor="custom-text" className="text-sm font-medium text-gray-100">
            Custom Text
          </label>
          <div className="flex gap-2">
            <input
              id="custom-text"
              type="text"
              value={customText}
              onChange={(e) => setCustomText(e.target.value)}
              placeholder="Enter custom status text..."
              className="flex-1 rounded-lg bg-gray-700 px-4 py-2 text-sm text-gray-100 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            <button 
              type="submit"
              className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-700"
            >
              Set
            </button>
          </div>
        </form>

        {/* Current State Display */}
        {state && (
          <div className="border-t border-gray-700 pt-4">
            <div className="space-y-1 text-xs text-gray-400">
              <p>Current: {state.mode}{state.text && ` - "${state.text}"`}</p>
              <p>Updated: {new Date(state.lastUpdated).toLocaleTimeString()}</p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}