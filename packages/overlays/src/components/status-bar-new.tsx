import { useDisplay } from '@/hooks/use-display'
import type { StatusBarMode } from '@landale/server'

interface StatusBarData {
  mode: StatusBarMode
  text?: string
  position: 'top' | 'bottom'
}

interface StatusBarProps {
  className?: string
}

const modeLabels: Record<StatusBarMode, string> = {
  preshow: 'Pre-Show',
  soapbox: 'Soapbox',
  game: 'Gaming',
  outro: 'Outro',
  break: 'On Break',
  custom: ''
}

export function StatusBar({ className }: StatusBarProps) {
  const { data, isConnected, isVisible } = useDisplay<StatusBarData>('statusBar')

  if (!data || !isVisible) {
    return null
  }

  const displayText = data.text || (data.mode !== 'custom' ? modeLabels[data.mode] : '')

  return (
    <div
      className={`absolute inset-x-0 bg-gray-900/95 backdrop-blur-sm border-gray-800 ${
        data.position === 'top' ? 'top-0 border-b' : 'bottom-0 border-t'
      } ${className || ''}`}
    >
      <div className="flex items-center justify-between px-6 py-3">
        <div className="flex items-center gap-4">
          {/* Connection indicator */}
          <div className={`h-2 w-2 rounded-full transition-colors ${
            isConnected ? 'bg-green-500' : 'bg-red-500'
          }`} />

          {/* Status text */}
          <div className="text-white font-medium text-lg">
            {displayText}
          </div>
        </div>

        {/* Optional: Add timestamps or other info on the right */}
        <div className="text-gray-400 text-sm font-mono">
          {new Date().toLocaleTimeString('en-US', { 
            hour12: false,
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
          })}
        </div>
      </div>
    </div>
  )
}