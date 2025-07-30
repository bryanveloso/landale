/**
 * Layer Orchestrator Tests
 * Focus on state management logic, not animation implementation
 */

import { describe, test, expect, beforeEach } from 'bun:test'
import { useLayerOrchestrator } from './use-layer-orchestrator'

// Simple mock element for registration
const createMockElement = (): HTMLElement => {
  const attributes: Record<string, string> = {}

  return {
    setAttribute: (name: string, value: string) => {
      attributes[name] = value
    },
    getAttribute: (name: string) => attributes[name] || null,
    hasAttribute: (name: string) => name in attributes,
    removeAttribute: (name: string) => {
      delete attributes[name]
    }
  } as unknown as HTMLElement
}

describe('Layer Orchestrator State Management', () => {
  let orchestrator: ReturnType<typeof useLayerOrchestrator>
  let mockElement: HTMLElement

  beforeEach(() => {
    orchestrator = useLayerOrchestrator()
    mockElement = createMockElement()
  })

  describe('Basic State Management', () => {
    test('initial state is hidden for all layers', () => {
      expect(orchestrator.getLayerState('foreground')).toBe('hidden')
      expect(orchestrator.getLayerState('midground')).toBe('hidden')
      expect(orchestrator.getLayerState('background')).toBe('hidden')
    })

    test('isLayerVisible returns false for hidden layers', () => {
      expect(orchestrator.isLayerVisible('background')).toBe(false)
    })

    test('registering element updates state to hidden with element attached', () => {
      orchestrator.registerLayer('background', mockElement)
      expect(orchestrator.getLayerState('background')).toBe('hidden')
      expect(mockElement.getAttribute('data-state')).toBe('hidden')
    })
  })

  describe('Race Condition Handling', () => {
    test('showLayer before registerLayer queues state change', () => {
      const content = { type: 'test-content', data: 'test' }

      // Call showLayer before element is registered
      orchestrator.showLayer('background', content)

      // State should be entering even without element
      expect(orchestrator.getLayerState('background')).toBe('entering')

      // Now register element - should process the queued state
      orchestrator.registerLayer('background', mockElement)
      expect(mockElement.getAttribute('data-state')).toBe('entering')
    })

    test('multiple showLayer calls before registration use latest content', () => {
      const content1 = { type: 'content-1', data: 'first' }
      const content2 = { type: 'content-2', data: 'second' }

      orchestrator.showLayer('background', content1)
      orchestrator.showLayer('background', content2)

      expect(orchestrator.getLayerState('background')).toBe('entering')

      orchestrator.registerLayer('background', mockElement)
      expect(mockElement.getAttribute('data-state')).toBe('entering')
    })

    test('showLayer after registration works normally', () => {
      const content = { type: 'test-content', data: 'test' }

      orchestrator.registerLayer('background', mockElement)
      orchestrator.showLayer('background', content)

      expect(orchestrator.getLayerState('background')).toBe('entering')
      expect(mockElement.getAttribute('data-state')).toBe('entering')
    })
  })

  describe('Layer Priority and Interruption', () => {
    beforeEach(() => {
      // Register all layers for priority testing
      orchestrator.registerLayer('foreground', createMockElement())
      orchestrator.registerLayer('midground', createMockElement())
      orchestrator.registerLayer('background', createMockElement())
    })

    test('higher priority content interrupts lower priority', () => {
      const bgContent = { type: 'stats', data: 'background' }
      const fgContent = { type: 'alert', data: 'urgent' }

      // Show background content first
      orchestrator.showLayer('background', bgContent)
      expect(orchestrator.getLayerState('background')).toBe('entering')

      // Show foreground content (higher priority)
      orchestrator.showLayer('foreground', fgContent)

      // Background should be interrupted, foreground should be entering
      expect(orchestrator.getLayerState('background')).toBe('interrupted')
      expect(orchestrator.getLayerState('foreground')).toBe('entering')
    })

    test('midground interrupts background but not foreground', () => {
      const bgContent = { type: 'stats', data: 'background' }
      const mgContent = { type: 'notification', data: 'midground' }
      const fgContent = { type: 'alert', data: 'foreground' }

      orchestrator.showLayer('background', bgContent)
      orchestrator.showLayer('foreground', fgContent)

      // Both should be active in their layers
      expect(orchestrator.getLayerState('background')).toBe('interrupted')
      expect(orchestrator.getLayerState('foreground')).toBe('entering')

      // Midground should interrupt background but not foreground
      orchestrator.showLayer('midground', mgContent)
      expect(orchestrator.getLayerState('background')).toBe('interrupted')
      expect(orchestrator.getLayerState('midground')).toBe('entering')
      expect(orchestrator.getLayerState('foreground')).toBe('entering')
    })

    test('hiding higher priority layer restores lower priority', () => {
      const bgContent = { type: 'stats', data: 'background' }
      const fgContent = { type: 'alert', data: 'urgent' }

      // Setup: background active, then foreground interrupts
      orchestrator.showLayer('background', bgContent)
      orchestrator.showLayer('foreground', fgContent)

      expect(orchestrator.getLayerState('background')).toBe('interrupted')
      expect(orchestrator.getLayerState('foreground')).toBe('entering')

      // Hide foreground - background should restore
      orchestrator.hideLayer('foreground')

      expect(orchestrator.getLayerState('foreground')).toBe('exiting')
      expect(orchestrator.getLayerState('background')).toBe('active')
    })
  })

  describe('State Transitions', () => {
    beforeEach(() => {
      orchestrator.registerLayer('background', mockElement)
    })

    test('showLayer transitions from hidden to entering', () => {
      const content = { type: 'test-content', data: 'test' }

      expect(orchestrator.getLayerState('background')).toBe('hidden')

      orchestrator.showLayer('background', content)
      expect(orchestrator.getLayerState('background')).toBe('entering')
      expect(mockElement.getAttribute('data-state')).toBe('entering')
    })

    test('hideLayer transitions to exiting', () => {
      const content = { type: 'test-content', data: 'test' }

      orchestrator.showLayer('background', content)
      expect(orchestrator.getLayerState('background')).toBe('entering')

      orchestrator.hideLayer('background')
      expect(orchestrator.getLayerState('background')).toBe('exiting')
      expect(mockElement.getAttribute('data-state')).toBe('exiting')
    })

    test('isLayerVisible returns true for entering and active states', () => {
      const content = { type: 'test-content', data: 'test' }

      expect(orchestrator.isLayerVisible('background')).toBe(false) // hidden

      orchestrator.showLayer('background', content)
      expect(orchestrator.isLayerVisible('background')).toBe(true) // entering

      orchestrator.hideLayer('background')
      expect(orchestrator.isLayerVisible('background')).toBe(false) // exiting
    })
  })

  describe('Memory Management', () => {
    test('unregisterLayer cleans up layer state', () => {
      orchestrator.registerLayer('background', mockElement)
      orchestrator.showLayer('background', { test: 'data' })

      expect(orchestrator.getLayerState('background')).toBe('entering')

      orchestrator.unregisterLayer('background')
      expect(orchestrator.getLayerState('background')).toBe('hidden')
    })

    test('can re-register layer after unregister', () => {
      orchestrator.registerLayer('background', mockElement)
      orchestrator.unregisterLayer('background')

      const newElement = createMockElement()
      orchestrator.registerLayer('background', newElement)

      expect(orchestrator.getLayerState('background')).toBe('hidden')
      expect(newElement.getAttribute('data-state')).toBe('hidden')
    })
  })

  describe('Edge Cases', () => {
    test('can call showLayer multiple times on same layer', () => {
      orchestrator.registerLayer('background', mockElement)

      const content1 = { type: 'content-1', data: 'first' }
      const content2 = { type: 'content-2', data: 'second' }

      orchestrator.showLayer('background', content1)
      expect(orchestrator.getLayerState('background')).toBe('entering')

      orchestrator.showLayer('background', content2)
      expect(orchestrator.getLayerState('background')).toBe('entering')
    })

    test('hideLayer on hidden layer does nothing', () => {
      orchestrator.registerLayer('background', mockElement)

      expect(orchestrator.getLayerState('background')).toBe('hidden')
      orchestrator.hideLayer('background')
      expect(orchestrator.getLayerState('background')).toBe('hidden')
    })

    test('can register same layer multiple times', () => {
      const element1 = createMockElement()
      const element2 = createMockElement()

      orchestrator.registerLayer('background', element1)
      expect(element1.getAttribute('data-state')).toBe('hidden')

      orchestrator.registerLayer('background', element2)
      expect(element2.getAttribute('data-state')).toBe('hidden')
    })
  })
})
