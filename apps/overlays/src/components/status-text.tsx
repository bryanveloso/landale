import { useEffect, useState } from 'react'
import { useDisplay } from '@/hooks/use-display'

interface StatusTextData {
  text: string
  position: 'top' | 'bottom'
  fontSize: 'small' | 'medium' | 'large'
  animation: 'none' | 'fade' | 'slide' | 'typewriter'
}

interface StatusTextProps {
  className?: string
}

const fontSizeClasses = {
  small: 'text-sm',
  medium: 'text-base',
  large: 'text-lg'
}

export function StatusText({ className }: StatusTextProps) {
  const { data, isVisible } = useDisplay<StatusTextData>('statusText')
  const [displayText, setDisplayText] = useState('')
  const [isAnimating, setIsAnimating] = useState(false)

  useEffect(() => {
    if (!data) return

    // Handle animation
    if (data.animation !== 'none' && data.text !== displayText) {
      setIsAnimating(true)
      setTimeout(
        () => {
          setDisplayText(data.text)
          setIsAnimating(false)
        },
        data.animation === 'fade' ? 150 : 0
      )
    } else {
      setDisplayText(data.text)
    }
  }, [data?.text, data?.animation])

  if (!data || !isVisible || !displayText) {
    return null
  }

  const animationClasses = {
    none: '',
    fade: `transition-opacity duration-300 ${isAnimating ? 'opacity-0' : 'opacity-100'}`,
    slide: `transition-transform duration-300 ${isAnimating ? 'translate-y-4' : 'translate-y-0'}`,
    typewriter: '' // Could implement typewriter effect later
  }

  return (
    <div className={`absolute inset-x-0 ${data.position === 'top' ? 'top-0' : 'bottom-0'} ${className || ''}`}>
      <div className="px-6 py-4">
        <div className={`text-white ${fontSizeClasses[data.fontSize]} ${animationClasses[data.animation]}`}>
          {displayText}
        </div>
      </div>
    </div>
  )
}
