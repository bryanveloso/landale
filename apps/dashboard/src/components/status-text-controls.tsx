import { useState } from 'react'
import { useDisplay } from '@/hooks/use-display'
import { Wifi, WifiOff, Eye, EyeOff, Type, Trash2 } from 'lucide-react'

interface StatusTextData {
  text: string
  position: 'top' | 'bottom'
  fontSize: 'small' | 'medium' | 'large'
  animation: 'none' | 'fade' | 'slide' | 'typewriter'
}

const presetMessages = [
  { label: 'Typing...', text: 'Typing a message...' },
  { label: 'Reading Chat', text: 'Reading chat...' },
  { label: 'BRB', text: 'Be right back!' },
  { label: 'Starting Soon', text: 'Starting soon...' },
  { label: 'Technical Issues', text: 'Experiencing technical difficulties...' },
  { label: 'Game Crashed', text: 'Game crashed, restarting...' }
]

export function StatusTextControls() {
  const { data, isConnected, isVisible, update, setVisibility, clear } = useDisplay<StatusTextData>('statusText')
  const [customText, setCustomText] = useState('')

  if (!data) return null

  const handleSetText = async (text: string) => {
    await update({ text })
  }

  const handleCustomTextSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (customText.trim()) {
      await handleSetText(customText)
    }
  }

  return (
    <div className="rounded-lg border border-gray-700 bg-gray-800 p-6">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-lg font-semibold text-gray-100">Status Text</h3>
        <div className="flex items-center gap-2">
          {isConnected ? <Wifi className="h-4 w-4 text-green-500" /> : <WifiOff className="h-4 w-4 text-red-500" />}
        </div>
      </div>

      <div className="space-y-6">
        {/* Visibility Toggle */}
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-gray-100">Show Status Text</span>
          <button
            onClick={() => setVisibility(!isVisible)}
            className={`flex h-10 w-10 items-center justify-center rounded-lg transition-colors ${
              isVisible ? 'bg-green-600 text-white hover:bg-green-700' : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
            }`}>
            {isVisible ? <Eye className="h-5 w-5" /> : <EyeOff className="h-5 w-5" />}
          </button>
        </div>

        {/* Quick Presets */}
        <div className="space-y-2">
          <span className="text-sm font-medium text-gray-100">Quick Presets</span>
          <div className="grid grid-cols-2 gap-2">
            {presetMessages.map((preset) => (
              <button
                key={preset.label}
                onClick={() => handleSetText(preset.text)}
                className="rounded-lg bg-gray-700 px-3 py-2 text-sm text-gray-300 transition-colors hover:bg-gray-600">
                {preset.label}
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
              className="flex-1 rounded-lg bg-gray-700 px-4 py-2 text-sm text-gray-100 placeholder-gray-400 focus:ring-2 focus:ring-blue-500 focus:outline-none"
            />
            <button
              type="submit"
              className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-700">
              <Type className="h-4 w-4" />
            </button>
            <button
              type="button"
              onClick={clear}
              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-red-700">
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        </form>

        {/* Settings */}
        <div className="space-y-4">
          <span className="text-sm font-medium text-gray-100">Settings</span>

          {/* Position */}
          <div className="flex gap-2">
            <button
              onClick={() => update({ position: 'top' })}
              className={`flex-1 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                data.position === 'top' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}>
              Top
            </button>
            <button
              onClick={() => update({ position: 'bottom' })}
              className={`flex-1 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                data.position === 'bottom' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}>
              Bottom
            </button>
          </div>

          {/* Font Size */}
          <div className="space-y-2">
            <span className="text-xs text-gray-400">Font Size</span>
            <div className="flex gap-2">
              {(['small', 'medium', 'large'] as const).map((size) => (
                <button
                  key={size}
                  onClick={() => update({ fontSize: size })}
                  className={`flex-1 rounded-lg px-3 py-2 text-sm font-medium capitalize transition-colors ${
                    data.fontSize === size ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                  }`}>
                  {size}
                </button>
              ))}
            </div>
          </div>

          {/* Animation */}
          <div className="space-y-2">
            <span className="text-xs text-gray-400">Animation</span>
            <div className="grid grid-cols-2 gap-2">
              {(['none', 'fade', 'slide', 'typewriter'] as const).map((animation) => (
                <button
                  key={animation}
                  onClick={() => update({ animation })}
                  className={`rounded-lg px-3 py-2 text-sm font-medium capitalize transition-colors ${
                    data.animation === animation
                      ? 'bg-blue-600 text-white'
                      : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                  }`}>
                  {animation}
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Current State Display */}
        <div className="border-t border-gray-700 pt-4">
          <div className="space-y-1 text-xs text-gray-400">
            <p>Current: {data.text || '(empty)'}</p>
          </div>
        </div>
      </div>
    </div>
  )
}
