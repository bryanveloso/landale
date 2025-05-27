/**
 * This is inspired by the classic Flying Toasters screensaver from After Dark.
 * It builds off of Bryan Braun's original implementation: https://github.com/bryanbraun/after-dark-css
 */

import { motion, AnimatePresence } from 'framer-motion'
import { useState, useEffect, useRef } from 'react'

interface SpriteConfig {
  name: string
  src: string | string[] // Single sprite sheet or array of individual frame files
  frameWidth: number
  frameHeight: number
  frameCount: number
  speeds: number[] // Array of possible durations in seconds
  delays: number[] // Array of possible delays in seconds
}

interface FlyingObjectProps {
  config: SpriteConfig
  speed: number
  delay: number
  startPosition: { x: number; y: number }
  onComplete: () => void
}

const FlyingObject = ({ config, speed, delay, startPosition, onComplete }: FlyingObjectProps) => {
  const [currentFrame, setCurrentFrame] = useState(0)

  // Sprite flapping animation - exactly matches CSS steps(4) at 0.2s
  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentFrame(prev => (prev + 1) % config.frameCount)
    }, 200 / config.frameCount) // 0.2s / 4 frames = 50ms per frame

    return () => clearInterval(interval)
  }, [config.frameCount])

  // Handle both sprite sheet and individual frame images
  const getSpriteStyle = () => {
    if (Array.isArray(config.src)) {
      // Individual frame files
      return {
        backgroundImage: `url(${config.src[currentFrame]})`,
        backgroundPosition: '0px 0px',
      }
    } else {
      // Sprite sheet
      return {
        backgroundImage: `url(${config.src})`,
        backgroundPosition: `${-currentFrame * config.frameWidth}px 0px`,
      }
    }
  }

  // Motion variants that exactly replicate CSS keyframes
  const flyVariants = {
    start: {
      x: startPosition.x,
      y: startPosition.y,
    },
    end: {
      x: startPosition.x - 1600, // Exact CSS transform distance
      y: startPosition.y + 1600,
      transition: {
        duration: speed,
        ease: 'linear', // Matches CSS linear animation
        delay,
      },
    },
  }

  return (
    <motion.div
      className="absolute pointer-events-none"
      style={{
        width: config.frameWidth,
        height: config.frameHeight,
        ...getSpriteStyle(),
        backgroundRepeat: 'no-repeat',
      }}
      variants={flyVariants}
      initial="start"
      animate="end"
      onAnimationComplete={onComplete}
    />
  )
}

interface FlyingToastersProps {
  sprites: SpriteConfig[]
  density?: number // How many objects to spawn
}

const FlyingToasters = ({ sprites, density = 20 }: FlyingToastersProps) => {
  const [objects, setObjects] = useState<Array<{
    id: string
    config: SpriteConfig
    speed: number
    delay: number
    startPosition: { x: number; y: number }
  }>>([])

  const containerRef = useRef<HTMLDivElement>(null)

  // Original positioning system - reverse "L" shaped batches
  const positionClasses = [
    // Batch 1 (-10% to -20%)
    // Top edge, from right to left
    { right: -2, top: -17 },
    { right: 10, top: -19 },
    { right: 20, top: -18 },
    { right: 30, top: -20 },
    { right: 40, top: -21 },
    { right: 50, top: -18 },
    { right: 60, top: -20 },
    // Right side, from top to bottom
    { right: -17, top: 10 },
    { right: -19, top: 20 },
    { right: -21, top: 30 },
    { right: -23, top: 50 },
    { right: -25, top: 70 },
    
    // Batch 2 (-20% to -40%)
    // Top edge, from right to left
    { right: 0, top: -26 },
    { right: 10, top: -20 },
    { right: 20, top: -36 },
    { right: 30, top: -24 },
    { right: 40, top: -33 },
    { right: 60, top: -40 },
    // Right side, from top to bottom
    { right: -26, top: 10 },
    { right: -36, top: 30 },
    { right: -29, top: 50 },
    
    // Batch 3 (-40% to -60%)
    // Top edge, from right to left
    { right: 0, top: -46 },
    { right: 10, top: -56 },
    { right: 20, top: -49 },
    { right: 30, top: -60 },
    // Right side, from top to bottom
    { right: -46, top: 10 },
    { right: -56, top: 20 },
    { right: -49, top: 30 },
  ]

  const currentPositionIndex = useRef(0)

  // Get next position from the predefined list (cycles through)
  const generateStartPosition = () => {
    if (!containerRef.current) return { x: 0, y: 0 }
    
    const container = containerRef.current
    const pos = positionClasses[currentPositionIndex.current]
    currentPositionIndex.current = (currentPositionIndex.current + 1) % positionClasses.length
    
    // Convert percentage-based positions to pixels
    // Note: CSS uses "right" so we need to calculate from right edge
    const x = container.clientWidth - (container.clientWidth * pos.right / 100)
    const y = container.clientHeight * pos.top / 100
    
    return { x, y }
  }

  // Spawn objects with exact original timing
  useEffect(() => {
    const spawnObject = () => {
      const config = sprites[Math.floor(Math.random() * sprites.length)]
      const speed = config.speeds[Math.floor(Math.random() * config.speeds.length)]
      const delay = config.delays[Math.floor(Math.random() * config.delays.length)]
      
      const newObject = {
        id: `${Date.now()}-${Math.random()}`,
        config,
        speed,
        delay,
        startPosition: generateStartPosition(),
      }

      setObjects(prev => [...prev, newObject])
    }

    // Initial spawn
    for (let i = 0; i < density; i++) {
      setTimeout(spawnObject, i * 200) // Stagger initial spawns
    }

    // Continuous spawning
    const interval = setInterval(spawnObject, 3000) // New object every 3 seconds

    return () => clearInterval(interval)
  }, [sprites, density])

  const handleObjectComplete = (id: string) => {
    setObjects(prev => prev.filter(obj => obj.id !== id))
    
    // Spawn replacement
    setTimeout(() => {
      const config = sprites[Math.floor(Math.random() * sprites.length)]
      const speed = config.speeds[Math.floor(Math.random() * config.speeds.length)]
      const delay = config.delays[Math.floor(Math.random() * config.delays.length)]
      
      const newObject = {
        id: `${Date.now()}-${Math.random()}`,
        config,
        speed,
        delay,
        startPosition: generateStartPosition(),
      }

      setObjects(prev => [...prev, newObject])
    }, Math.random() * 2000) // Random respawn delay
  }

  return (
    <div 
      ref={containerRef}
      className="fixed inset-0 overflow-hidden bg-black"
      style={{ zIndex: -1 }}
    >
      <AnimatePresence>
        {objects.map(obj => (
          <FlyingObject
            key={obj.id}
            config={obj.config}
            speed={obj.speed}
            delay={obj.delay}
            startPosition={obj.startPosition}
            onComplete={() => handleObjectComplete(obj.id)}
          />
        ))}
      </AnimatePresence>
    </div>
  )
}

// Default toaster configuration with exact original timing
export const defaultToasterConfig: SpriteConfig = {
  name: 'toaster',
  src: '/sprites/toaster-sprite.gif',
  frameWidth: 64,
  frameHeight: 64,
  frameCount: 4,
  speeds: [10, 16, 24], // Exact CSS durations
  delays: [0, 4, 5, 8, 12, 16, 20], // Exact CSS delays
}

// Create separate configs for each toast variant
export const toast0Config: SpriteConfig = {
  name: 'toast0',
  src: '/sprites/toast0.gif',
  frameWidth: 64,
  frameHeight: 64,
  frameCount: 1, // Static image, no animation
  speeds: [12, 18, 20],
  delays: [0, 2, 6, 10, 14]
}

export const toast1Config: SpriteConfig = {
  name: 'toast1',
  src: '/sprites/toast1.gif',
  frameWidth: 64,
  frameHeight: 64,
  frameCount: 1,
  speeds: [12, 18, 20],
  delays: [0, 2, 6, 10, 14]
}

export const toast2Config: SpriteConfig = {
  name: 'toast2',
  src: '/sprites/toast2.gif',
  frameWidth: 64,
  frameHeight: 64,
  frameCount: 1,
  speeds: [12, 18, 20],
  delays: [0, 2, 6, 10, 14]
}

export const toast3Config: SpriteConfig = {
  name: 'toast3',
  src: '/sprites/toast3.gif',
  frameWidth: 64,
  frameHeight: 64,
  frameCount: 1,
  speeds: [12, 18, 20],
  delays: [0, 2, 6, 10, 14]
}

export default FlyingToasters
