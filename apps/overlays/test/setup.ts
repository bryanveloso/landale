/**
 * Test setup for Bun + happy-dom environment
 * Configures DOM simulation for testing overlay components
 */

import { Window } from 'happy-dom'

// Set up happy-dom environment for DOM simulation
const window = new Window()
global.document = window.document
global.window = window
global.HTMLElement = window.HTMLElement

// Add missing DOM APIs that GSAP needs
global.getComputedStyle = () => ({
  getPropertyValue: (prop: string) => {
    if (prop === 'transform') return 'matrix(1, 0, 0, 1, 0, 0)'
    return '0px'
  },
  width: '0px',
  height: '0px',
  transform: 'matrix(1, 0, 0, 1, 0, 0)'
})

global.requestAnimationFrame = (callback: FrameRequestCallback) => {
  return setTimeout(callback, 16) // 60fps
}

global.cancelAnimationFrame = (id: number) => {
  clearTimeout(id)
}

// Mock GSAP for predictable animation testing
const mockTimeline = {
  to: () => mockTimeline,
  fromTo: () => mockTimeline,
  call: (callback: () => void) => {
    // Immediately call the callback for testing
    callback()
    return mockTimeline
  },
  set: () => mockTimeline,
  kill: () => mockTimeline
}

// Mock GSAP context for memory leak testing
const mockContext = {
  add: (fn: () => void) => {
    // Execute the function to trigger animations
    fn()
  },
  revert: () => {
    // Mock revert behavior
  }
}

// @ts-expect-error - Mock GSAP globally
globalThis.gsap = {
  set: () => {},
  to: () => mockTimeline,
  fromTo: () => mockTimeline,
  timeline: (config?: { onComplete?: () => void }) => {
    // If there's an onComplete callback, call it immediately for testing
    if (config?.onComplete) {
      setTimeout(config.onComplete, 0)
    }
    return mockTimeline
  },
  context: (fn?: () => void, _element?: HTMLElement) => {
    // Call the function if provided (for initialization)
    if (fn) fn()
    return mockContext
  },
  killTweensOf: () => {}
}

// Add global test utilities
declare global {
  interface Window {
    testUtils: {
      createMockElement: () => HTMLElement
      waitFor: (callback: () => boolean, timeout?: number) => Promise<void>
    }
  }
}

globalThis.testUtils = {
  /**
   * Creates a mock DOM element for testing
   */
  createMockElement(): HTMLElement {
    const element = document.createElement('div')
    // Track setAttribute calls for testing
    const originalSetAttribute = element.setAttribute.bind(element)
    element.setAttribute = (name: string, value: string) => {
      originalSetAttribute(name, value)
    }
    return element
  },

  /**
   * Utility to wait for async conditions in tests
   */
  async waitFor(callback: () => boolean, timeout = 1000): Promise<void> {
    const start = Date.now()

    while (Date.now() - start < timeout) {
      if (callback()) {
        return
      }
      await new Promise((resolve) => setTimeout(resolve, 10))
    }

    throw new Error(`Condition not met within ${timeout}ms`)
  }
}

// Mock console methods for cleaner test output
global.console = {
  ...console,
  // Suppress debug logs in tests
  debug: () => {},
  // Keep errors and warnings
  error: console.error,
  warn: console.warn,
  log: console.log
}
