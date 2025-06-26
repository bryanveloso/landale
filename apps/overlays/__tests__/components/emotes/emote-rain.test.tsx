import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render } from '@testing-library/react'
import { EmoteRain } from '@/components/emotes/emote-rain'
import { emoteQueue } from '@/lib/emote-queue'

// Mock Matter.js with all required methods
vi.mock('matter-js', () => ({
  default: {
    Engine: {
      create: vi.fn(() => ({
        world: { bodies: [] },
        timing: { timestamp: 0 }
      })),
      update: vi.fn(),
      clear: vi.fn()
    },
    Render: {
      create: vi.fn(() => ({
        canvas: document.createElement('canvas'),
        options: {},
        context: {}
      })),
      run: vi.fn(),
      stop: vi.fn()
    },
    Runner: {
      create: vi.fn(() => ({ enabled: true })),
      run: vi.fn(),
      stop: vi.fn()
    },
    World: {
      add: vi.fn(),
      remove: vi.fn(),
      clear: vi.fn()
    },
    Bodies: {
      rectangle: vi.fn((x, y, w, h, opts) => ({
        id: Math.random(),
        position: { x, y },
        ...opts
      })),
      circle: vi.fn((x, y, r, opts) => ({
        id: Math.random(),
        position: { x, y },
        ...opts
      }))
    },
    Body: {
      applyForce: vi.fn(),
      setVelocity: vi.fn()
    },
    Events: {
      on: vi.fn()
    },
    Composite: {
      add: vi.fn(),
      allBodies: vi.fn(() => [])
    }
  }
}))

// Mock emote queue
vi.mock('@/lib/emote-queue', () => ({
  emoteQueue: {
    on: vi.fn(),
    off: vi.fn(),
    queueEmote: vi.fn()
  }
}))

describe('EmoteRain', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('should render canvas element', () => {
    render(<EmoteRain />)
    const canvas = document.querySelector('canvas')
    expect(canvas).toBeTruthy()
  })

  it('should subscribe to emote queue on mount', () => {
    render(<EmoteRain />)

    // Check that we subscribed to the emote queue
    expect(emoteQueue.on).toHaveBeenCalledWith('emote', expect.any(Function))
  })

  it('should handle window resize with throttling', async () => {
    const { container } = render(<EmoteRain />)

    // Trigger multiple resize events rapidly
    for (let i = 0; i < 10; i++) {
      window.dispatchEvent(new Event('resize'))
      await new Promise((resolve) => setTimeout(resolve, 10))
    }

    // Should not crash and canvas should still exist
    const canvas = container.querySelector('canvas')
    expect(canvas).toBeTruthy()
  })

  it('should clean up resources on unmount', () => {
    const { unmount } = render(<EmoteRain />)

    // Get the handler that was registered
    const handler = vi.mocked(emoteQueue.on).mock.calls[0][1]

    // Unmount
    unmount()

    // Should unsubscribe with the same handler
    expect(emoteQueue.off).toHaveBeenCalledWith('emote', handler)
  })

  it('should apply correct styles to container', () => {
    const { container } = render(<EmoteRain />)
    const wrapper = container.firstChild as HTMLElement

    expect(wrapper.className).toContain('fixed')
    expect(wrapper.className).toContain('inset-0')
    expect(wrapper.className).toContain('pointer-events-none')
  })
})
