import { useEffect, useState } from 'react'
import { trpcClient } from '@/lib/trpc'
import type { StatusTextState } from '@landale/server'

interface StatusTextProps {
  className?: string
}

const fontSizeClasses = {
  small: 'text-sm',
  medium: 'text-base',
  large: 'text-lg'
}

export function StatusText({ className }: StatusTextProps) {
  const [state, setState] = useState<StatusTextState | null>(null)
  const [isConnected, setIsConnected] = useState(false)
  const [displayText, setDisplayText] = useState('')
  const [isAnimating, setIsAnimating] = useState(false)

  useEffect(() => {
    const subscription = trpcClient.control.statusText.onUpdate.subscribe(undefined, {
      onData: (data) => {
        setState(data)
        setIsConnected(true)
        
        // Handle animation
        if (data.animation !== 'none' && data.text !== displayText) {
          setIsAnimating(true)
          setTimeout(() => {
            setDisplayText(data.text)
            setIsAnimating(false)
          }, data.animation === 'fade' ? 150 : 0)
        } else {
          setDisplayText(data.text)
        }
      },
      onError: (error) => {
        console.error('[StatusText] Subscription error:', error)
        setIsConnected(false)
      }
    })

    return () => {
      subscription.unsubscribe()
    }
  }, [displayText])

  if (!state || !state.isVisible || !displayText) {
    return null
  }

  const animationClasses = {
    none: '',
    fade: `transition-opacity duration-300 ${isAnimating ? 'opacity-0' : 'opacity-100'}`,
    slide: `transition-transform duration-300 ${isAnimating ? 'translate-y-4' : 'translate-y-0'}`,
    typewriter: '' // Could implement typewriter effect later
  }

  return (
    <div
      className={`absolute inset-x-0 ${
        state.position === 'top' ? 'top-0' : 'bottom-0'
      } ${className || ''}`}
    >
      <div className="px-6 py-4">
        <div className={`text-white ${fontSizeClasses[state.fontSize]} ${animationClasses[state.animation]}`}>
          {displayText}
        </div>
      </div>
    </div>
  )
}