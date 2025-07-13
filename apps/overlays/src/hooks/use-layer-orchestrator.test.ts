/**
 * Layer Orchestrator Tests
 * TDD approach to fixing race condition between registration and showLayer calls
 */

import { describe, test, expect, beforeEach } from 'bun:test'
import { useLayerOrchestrator } from './use-layer-orchestrator'
import type { LayerPriority } from './use-layer-orchestrator'

describe('Layer Orchestrator', () => {
  let orchestrator: ReturnType<typeof useLayerOrchestrator>
  let mockElement: HTMLElement

  beforeEach(() => {
    orchestrator = useLayerOrchestrator()
    mockElement = testUtils.createMockElement()
  })

  describe('Race Condition Fix', () => {
    test('showLayer called before registration should eventually reach active state', async () => {
      // This test should FAIL with the current implementation
      // Reproduces the bug where layer gets stuck in "entering" state
      
      const priority: LayerPriority = 'background'
      const content = { type: 'test-content', data: 'test' }
      
      // Call showLayer BEFORE registering the element (race condition)
      orchestrator.showLayer(priority, content)
      
      // Layer should be in 'entering' state but stuck because no element
      expect(orchestrator.getLayerState(priority)).toBe('entering')
      
      // Now register the element (simulating delayed onMount)
      orchestrator.registerLayer(priority, mockElement)
      
      // After registration, the layer should eventually reach 'active' state
      // This will fail because current implementation has early return when element is null
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState(priority) === 'active'
      }, 2000)
      
      expect(orchestrator.getLayerState(priority)).toBe('active')
    })

    test('showLayer after registration should work normally', async () => {
      // This test should PASS - normal flow works fine
      
      const priority: LayerPriority = 'background'
      const content = { type: 'test-content', data: 'test' }
      
      // Register element first (normal flow)
      orchestrator.registerLayer(priority, mockElement)
      
      // Then call showLayer
      orchestrator.showLayer(priority, content)
      
      // Should immediately be in entering state
      expect(orchestrator.getLayerState(priority)).toBe('entering')
      
      // Should transition to active (mocked GSAP calls onComplete immediately)
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState(priority) === 'active'
      })
      
      expect(orchestrator.getLayerState(priority)).toBe('active')
    })

    test('multiple showLayer calls before registration should work', async () => {
      // Edge case: multiple content updates before registration
      
      const priority: LayerPriority = 'background'
      const content1 = { type: 'content-1', data: 'first' }
      const content2 = { type: 'content-2', data: 'second' }
      
      // Multiple showLayer calls before registration
      orchestrator.showLayer(priority, content1)
      orchestrator.showLayer(priority, content2)
      
      // Should still be in entering state
      expect(orchestrator.getLayerState(priority)).toBe('entering')
      
      // Register element
      orchestrator.registerLayer(priority, mockElement)
      
      // Should process the latest state change and reach active
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState(priority) === 'active'
      })
      
      expect(orchestrator.getLayerState(priority)).toBe('active')
    })
  })

  describe('State Transitions', () => {
    beforeEach(() => {
      // Register element first for these tests
      orchestrator.registerLayer('background', mockElement)
    })

    test('normal state flow: hidden -> entering -> active', async () => {
      const priority: LayerPriority = 'background'
      const content = { type: 'test-content', data: 'test' }
      
      // Initial state
      expect(orchestrator.getLayerState(priority)).toBe('hidden')
      
      // Show layer
      orchestrator.showLayer(priority, content)
      expect(orchestrator.getLayerState(priority)).toBe('entering')
      
      // Wait for transition to active
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState(priority) === 'active'
      })
      
      expect(orchestrator.getLayerState(priority)).toBe('active')
    })

    test('hide layer: active -> exiting -> hidden', async () => {
      const priority: LayerPriority = 'background'
      const content = { type: 'test-content', data: 'test' }
      
      // Get to active state
      orchestrator.showLayer(priority, content)
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState(priority) === 'active'
      })
      
      // Hide layer
      orchestrator.hideLayer(priority)
      expect(orchestrator.getLayerState(priority)).toBe('exiting')
      
      // Wait for transition to hidden
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState(priority) === 'hidden'
      })
      
      expect(orchestrator.getLayerState(priority)).toBe('hidden')
    })
  })

  describe('Layer Priority and Interruption', () => {
    beforeEach(() => {
      // Register all layers
      orchestrator.registerLayer('foreground', testUtils.createMockElement())
      orchestrator.registerLayer('midground', testUtils.createMockElement())
      orchestrator.registerLayer('background', testUtils.createMockElement())
    })

    test('higher priority interrupts lower priority', async () => {
      const backgroundContent = { type: 'stats', data: 'background' }
      const foregroundContent = { type: 'alert', data: 'urgent' }
      
      // Show background content first
      orchestrator.showLayer('background', backgroundContent)
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState('background') === 'active'
      })
      
      // Show foreground content (higher priority)
      orchestrator.showLayer('foreground', foregroundContent)
      
      // Background should be interrupted
      expect(orchestrator.getLayerState('background')).toBe('interrupted')
      expect(orchestrator.getLayerState('foreground')).toBe('entering')
      
      // Foreground should become active
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState('foreground') === 'active'
      })
      
      expect(orchestrator.getLayerState('foreground')).toBe('active')
    })

    test('interrupted layer restores when higher priority exits', async () => {
      const backgroundContent = { type: 'stats', data: 'background' }
      const foregroundContent = { type: 'alert', data: 'urgent' }
      
      // Background active, then foreground interrupts
      orchestrator.showLayer('background', backgroundContent)
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState('background') === 'active'
      })
      
      orchestrator.showLayer('foreground', foregroundContent)
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState('foreground') === 'active'
      })
      
      expect(orchestrator.getLayerState('background')).toBe('interrupted')
      
      // Hide foreground
      orchestrator.hideLayer('foreground')
      await testUtils.waitFor(() => {
        return orchestrator.getLayerState('foreground') === 'hidden'
      })
      
      // Background should restore to active
      expect(orchestrator.getLayerState('background')).toBe('active')
    })
  })

  describe('isLayerVisible utility', () => {
    test('returns correct visibility states', () => {
      const priority: LayerPriority = 'background'
      
      // Hidden state
      expect(orchestrator.isLayerVisible(priority)).toBe(false)
      
      // TODO: Test other states when they work properly
      // This will help verify the race condition fix
    })
  })
})