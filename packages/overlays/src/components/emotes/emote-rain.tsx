import { useEffect, useRef, useState, memo, useCallback } from 'react'
import Matter from 'matter-js'

interface EmoteConfig {
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

interface EmoteBody {
  id: string
  emoteId: string
  body: Matter.Body
  createdAt: number
}

// Configuration options - adjust these to change behavior
const DEFAULT_CONFIG: EmoteConfig = {
  size: 112,              // Emote size in pixels (28, 56, 112, 168, 224)
  lifetime: 30000,        // How long emotes stay on screen (ms)
  gravity: 1,             // Gravity strength (0.1 - 3)
  restitution: 0.4,       // Bounciness (0 = no bounce, 1 = perfect bounce)
  friction: 0.3,          // Surface friction (0 = ice, 1 = sandpaper)
  airFriction: 0.001,     // Air resistance (0 = vacuum, 0.05 = molasses)
  spawnDelay: 100,        // Min delay between spawns (ms) - prevents spam
  maxEmotes: 200,         // Max emotes on screen at once
  rotationSpeed: 0.2      // Max rotation speed
}

export const EmoteRain = memo(function EmoteRain() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const engineRef = useRef<Matter.Engine | null>(null)
  const renderRef = useRef<Matter.Render | null>(null)
  const emoteBodiesRef = useRef<Map<string, EmoteBody>>(new Map())
  const spawnQueueRef = useRef<string[]>([])
  const lastSpawnTimeRef = useRef<number>(0)
  const [config] = useState<EmoteConfig>(DEFAULT_CONFIG)

  useEffect(() => {
    if (!canvasRef.current) return

    const canvas = canvasRef.current
    const width = window.innerWidth
    const height = window.innerHeight
    canvas.width = width
    canvas.height = height

    // Create Matter.js engine
    const engine = Matter.Engine.create({
      gravity: { x: 0, y: config.gravity }
    })
    engineRef.current = engine

    // Create renderer
    const render = Matter.Render.create({
      canvas,
      engine,
      options: {
        width,
        height,
        wireframes: false,
        background: 'transparent',
        showVelocity: false,
        showAngleIndicator: false
      }
    })
    renderRef.current = render

    // Create boundaries
    const wallThickness = 100
    const ground = Matter.Bodies.rectangle(
      width / 2,
      height + wallThickness / 2,
      width,
      wallThickness,
      { isStatic: true, render: { visible: false } }
    )
    
    const leftWall = Matter.Bodies.rectangle(
      -wallThickness / 2,
      height / 2,
      wallThickness,
      height,
      { isStatic: true, render: { visible: false } }
    )
    
    const rightWall = Matter.Bodies.rectangle(
      width + wallThickness / 2,
      height / 2,
      wallThickness,
      height,
      { isStatic: true, render: { visible: false } }
    )

    Matter.Composite.add(engine.world, [ground, leftWall, rightWall])

    // Run the renderer
    Matter.Render.run(render)

    // Create runner
    const runner = Matter.Runner.create()
    Matter.Runner.run(runner, engine)

    // Handle window resize
    const handleResize = () => {
      canvas.width = window.innerWidth
      canvas.height = window.innerHeight
      render.canvas.width = window.innerWidth
      render.canvas.height = window.innerHeight
      
      // Update ground position
      Matter.Body.setPosition(ground, {
        x: window.innerWidth / 2,
        y: window.innerHeight + wallThickness / 2
      })
      
      // Update wall positions
      Matter.Body.setPosition(leftWall, {
        x: -wallThickness / 2,
        y: window.innerHeight / 2
      })
      
      Matter.Body.setPosition(rightWall, {
        x: window.innerWidth + wallThickness / 2,
        y: window.innerHeight / 2
      })
    }

    window.addEventListener('resize', handleResize)

    // Cleanup function
    return () => {
      window.removeEventListener('resize', handleResize)
      Matter.Render.stop(render)
      Matter.Runner.stop(runner)
      Matter.Engine.clear(engine)
      emoteBodiesRef.current.clear()
    }
  }, [config.gravity])

  // Method to queue an emote for spawning
  const queueEmote = useCallback((emoteId: string) => {
    spawnQueueRef.current.push(emoteId)
  }, [])

  // Method to spawn an emote from the queue
  const spawnEmoteFromQueue = () => {
    if (!engineRef.current || spawnQueueRef.current.length === 0) return
    
    // Check if we've hit the max emote limit
    if (emoteBodiesRef.current.size >= config.maxEmotes) return
    
    // Check spawn delay
    const now = Date.now()
    if (now - lastSpawnTimeRef.current < config.spawnDelay) return
    
    const emoteId = spawnQueueRef.current.shift()!
    lastSpawnTimeRef.current = now

    const x = Math.random() * window.innerWidth
    const y = -config.size // Start above the screen
    const rotation = Math.random() * Math.PI * 2

    // Create the physics body
    const body = Matter.Bodies.rectangle(x, y, config.size, config.size, {
      restitution: config.restitution,
      friction: config.friction,
      frictionAir: config.airFriction,
      angle: rotation,
      render: {
        sprite: {
          texture: `/emotes/${emoteId}_30.png`, // Using the 3.0 size (112px)
          xScale: config.size / 112,
          yScale: config.size / 112
        }
      }
    })

    // Add some initial angular velocity for rotation
    Matter.Body.setAngularVelocity(body, (Math.random() - 0.5) * config.rotationSpeed)

    // Add to the world
    Matter.Composite.add(engineRef.current.world, body)

    // Track the emote
    const emoteBody: EmoteBody = {
      id: `${emoteId}-${Date.now()}-${Math.random()}`,
      emoteId,
      body,
      createdAt: Date.now()
    }
    emoteBodiesRef.current.set(emoteBody.id, emoteBody)

    // Schedule removal after lifetime
    setTimeout(() => {
      removeEmote(emoteBody.id)
    }, config.lifetime)
  }

  // Method to remove an emote with falling effect
  const removeEmote = (id: string) => {
    const emoteBody = emoteBodiesRef.current.get(id)
    if (!emoteBody || !engineRef.current) return

    // Remove collision by setting it to a different category
    emoteBody.body.collisionFilter.category = 0x0002
    emoteBody.body.collisionFilter.mask = 0x0000

    // Apply downward force to make it fall through the bottom
    Matter.Body.applyForce(emoteBody.body, emoteBody.body.position, {
      x: 0,
      y: 0.1
    })

    // Remove from tracking
    emoteBodiesRef.current.delete(id)

    // Remove from world after it's off screen
    setTimeout(() => {
      if (engineRef.current?.world) {
        Matter.Composite.remove(engineRef.current.world, emoteBody.body)
      }
    }, 3000)
  }

  // Process spawn queue
  useEffect(() => {
    const interval = setInterval(() => {
      spawnEmoteFromQueue()
    }, 50) // Check queue every 50ms

    return () => clearInterval(interval)
  }, [])

  // Expose queue method for external use
  useEffect(() => {
    (window as any).queueEmote = queueEmote
    return () => {
      delete (window as any).queueEmote
    }
  }, [queueEmote])

  return (
    <canvas
      ref={canvasRef}
      className="fixed inset-0 pointer-events-none"
      style={{ zIndex: 9999 }}
    />
  )
})
