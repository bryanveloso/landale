import { useEffect, useState } from 'react'
import { trpcClient } from '@/lib/trpc'
import type { StatusBarState } from '@landale/server'

interface StatusBarProps {
  className?: string
}

const modeLabels: Record<StatusBarState['mode'], string> = {
  preshow: 'Pre-Show',
  soapbox: 'Soapbox',
  game: 'Gaming',
  outro: 'Outro',
  break: 'On Break',
  custom: ''
}

export function StatusBar({ className }: StatusBarProps) {
  const [state, setState] = useState<StatusBarState | null>(null)
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    const subscription = trpcClient.control.statusBar.onUpdate.subscribe(undefined, {
      onData: (data) => {
        setState(data)
        setIsConnected(true)
      },
      onError: (error) => {
        console.error('[StatusBar] Subscription error:', error)
        setIsConnected(false)
      }
    })

    return () => {
      subscription.unsubscribe()
    }
  }, [])

  if (!state || !state.isVisible) {
    return null
  }

  const displayText = state.text || (state.mode !== 'custom' ? modeLabels[state.mode] : '')

  return (
    <div
      className={`absolute inset-x-0 bg-gray-900/95 backdrop-blur-sm border-gray-800 ${
        state.position === 'top' ? 'top-0 border-b' : 'bottom-0 border-t'
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