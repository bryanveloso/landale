import { useDisplay } from '@/hooks/use-display'
import type { StatusBarMode } from '@landale/server'
import { Wifi, WifiOff, Eye, EyeOff } from 'lucide-react'

interface StatusBarData {
  mode: StatusBarMode
  text?: string
  position: 'top' | 'bottom'
}

const modeOptions: { value: StatusBarMode; label: string }[] = [
  { value: 'preshow', label: 'Pre-Show' },
  { value: 'soapbox', label: 'Soapbox' },
  { value: 'game', label: 'Gaming' },
  { value: 'outro', label: 'Outro' },
  { value: 'break', label: 'On Break' },
  { value: 'custom', label: 'Custom' }
]

export function StatusBarControls() {
  const { data, isConnected, isVisible, update, setVisibility } = useDisplay<StatusBarData>('statusBar')

  if (!data) return null

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
            onClick={() => setVisibility(!isVisible)}
            className={`flex h-10 w-10 items-center justify-center rounded-lg transition-colors ${
              isVisible 
                ? 'bg-green-600 text-white hover:bg-green-700' 
                : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
            }`}
          >
            {isVisible ? <Eye className="h-5 w-5" /> : <EyeOff className="h-5 w-5" />}
          </button>
        </div>

        {/* Position */}
        <div className="space-y-2">
          <span className="text-sm font-medium text-gray-100">Position</span>
          <div className="flex gap-2">
            <button
              onClick={() => update({ position: 'top' })}
              className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                data.position === 'top'
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              Top
            </button>
            <button
              onClick={() => update({ position: 'bottom' })}
              className={`flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                data.position === 'bottom'
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
                onClick={() => update({ mode: option.value })}
                className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                  data.mode === option.value
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}