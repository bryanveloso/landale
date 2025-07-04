import { describe, it, expect, beforeEach, afterEach, mock, spyOn } from 'bun:test'
import { render } from '@testing-library/react'
import { EmoteRain } from '@/components/emotes/emote-rain'
import { emoteQueue } from '@/lib/emote-queue'

// Mock Matter.js with all required methods
const mockEngine = {
  world: { bodies: [] },
  timing: { timestamp: 0 }
}

const mockRender = {
  canvas: document.createElement('canvas'),
  options: {},
  context: {}
}

const mockRunner = { enabled: true }

const Matter = {
  Engine: {
    create: mock(() => mockEngine),
    update: mock(),
    clear: mock()
  },
  Render: {
    create: mock(() => mockRender),
    run: mock(),
    stop: mock()
  },
  Runner: {
    create: mock(() => mockRunner),
    run: mock(),
    stop: mock()
  },
  World: {
    add: mock(),
    remove: mock(),
    clear: mock()
  },
  Bodies: {
    rectangle: mock((_x: number, _y: number, _w: number, _h: number, opts?: unknown) => ({
      id: Math.random(),
      position: { x: _x, y: _y },
      ...((opts ?? {}) as object)
    }))
  },
  Composite: {
    add: mock(),
    remove: mock(),
    allBodies: mock(() => [])
  },
  Events: {
    on: mock(),
    off: mock()
  }
}

// Replace the module
import.meta.mock('matter-js', () => ({
  default: Matter
}))

// Mock the emote queue
const mockQueueListener = mock()
spyOn(emoteQueue, 'addListener').mockImplementation(mockQueueListener)
spyOn(emoteQueue, 'removeListener').mockImplementation(mock())

describe('EmoteRain', () => {
  beforeEach(() => {
    // Clear all mocks before each test
    Object.values(Matter).forEach(module => {
      Object.values(module).forEach(fn => {
        if (typeof fn === 'function' && 'mockClear' in fn) {
          (fn as any).mockClear()
        }
      })
    })
    mockQueueListener.mockClear()
  })

  afterEach(() => {
    // Clean up any DOM elements
    document.body.innerHTML = ''
  })

  it('should render canvas element', () => {
    const { container } = render(<EmoteRain />)
    const canvas = container.querySelector('canvas')
    expect(canvas).toBeTruthy()
  })

  it('should initialize Matter.js physics engine', () => {
    render(<EmoteRain />)

    expect(Matter.Engine.create).toHaveBeenCalled()
    expect(Matter.Render.create).toHaveBeenCalled()
    expect(Matter.Runner.create).toHaveBeenCalled()
  })

  it('should register emote queue listener', () => {
    render(<EmoteRain />)

    expect(emoteQueue.addListener).toHaveBeenCalled()
  })

  it('should clean up on unmount', () => {
    const { unmount } = render(<EmoteRain />)

    unmount()

    expect(Matter.Render.stop).toHaveBeenCalled()
    expect(Matter.Runner.stop).toHaveBeenCalled()
    expect(Matter.Engine.clear).toHaveBeenCalled()
    expect(Matter.World.clear).toHaveBeenCalled()
    expect(emoteQueue.removeListener).toHaveBeenCalled()
  })

  it('should handle emote spawn from queue', () => {
    render(<EmoteRain />)

    // Get the listener that was registered
    const listener = mockQueueListener.mock.calls[0][0]

    // Simulate an emote being added to queue
    const mockEmote = {
      id: 'test-emote',
      url: 'https://example.com/emote.png',
      name: 'TestEmote'
    }

    listener(mockEmote)

    // Verify that a body was created for the emote
    expect(Matter.Bodies.rectangle).toHaveBeenCalled()
    expect(Matter.World.add).toHaveBeenCalled()
  })

  it('should handle multiple emotes', () => {
    render(<EmoteRain />)

    const listener = mockQueueListener.mock.calls[0][0]

    // Add multiple emotes
    const emotes = [
      { id: 'emote1', url: 'https://example.com/1.png', name: 'Emote1' },
      { id: 'emote2', url: 'https://example.com/2.png', name: 'Emote2' },
      { id: 'emote3', url: 'https://example.com/3.png', name: 'Emote3' }
    ]

    emotes.forEach(emote => listener(emote))

    // Should create a body for each emote
    expect(Matter.Bodies.rectangle).toHaveBeenCalledTimes(emotes.length)
    expect(Matter.World.add).toHaveBeenCalledTimes(emotes.length)
  })
})
