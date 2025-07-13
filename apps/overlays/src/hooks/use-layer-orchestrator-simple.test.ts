/**
 * Simplified Layer Orchestrator Tests - Focus on Race Condition Logic
 * Tests the core state management without GSAP complications
 */

import { describe, test, expect, beforeEach } from 'bun:test'
import { createSignal } from 'solid-js'

// Simplified version of the orchestrator to test the core logic
type LayerPriority = 'foreground' | 'midground' | 'background'
type LayerState = 'hidden' | 'entering' | 'active' | 'interrupted' | 'exiting'

function createSimpleOrchestrator() {
  const [layerStates, setLayerStates] = createSignal<Record<LayerPriority, LayerState>>({
    foreground: 'hidden',
    midground: 'hidden', 
    background: 'hidden'
  })

  const layerElements: Record<LayerPriority, HTMLElement | null> = {
    foreground: null,
    midground: null,
    background: null
  }

  // This is the current problematic implementation
  const updateLayerState = (priority: LayerPriority, newState: LayerState) => {
    setLayerStates(prev => ({
      ...prev,
      [priority]: newState
    }))

    const element = layerElements[priority]
    if (!element) {
      // THIS IS THE BUG: Early return leaves state inconsistent
      console.log(`No element for ${priority}, state set to ${newState} but no animation`)
      return
    }

    // Simulate animation completion
    if (newState === 'entering') {
      setTimeout(() => {
        setLayerStates(prev => ({
          ...prev,
          [priority]: 'active'
        }))
      }, 10)
    }
  }

  const registerLayer = (priority: LayerPriority, element: HTMLElement) => {
    layerElements[priority] = element
    console.log(`Registered ${priority} layer`)
  }

  const showLayer = (priority: LayerPriority, content: any) => {
    const currentState = layerStates()[priority]
    
    if (currentState === 'hidden') {
      updateLayerState(priority, 'entering')
    }
  }

  const getLayerState = (priority: LayerPriority) => {
    return layerStates()[priority]
  }

  return {
    registerLayer,
    showLayer,
    getLayerState,
    layerStates
  }
}

describe('Layer Orchestrator Race Condition (Simplified)', () => {
  let orchestrator: ReturnType<typeof createSimpleOrchestrator>
  let mockElement: HTMLElement

  beforeEach(() => {
    orchestrator = createSimpleOrchestrator()
    mockElement = testUtils.createMockElement()
  })

  test('RACE CONDITION: showLayer before registration gets stuck in entering state', async () => {
    // This test demonstrates the current bug
    const priority: LayerPriority = 'background'
    const content = { type: 'test-content' }

    // Call showLayer BEFORE registering element (race condition)
    orchestrator.showLayer(priority, content)

    // State should be 'entering' 
    expect(orchestrator.getLayerState(priority)).toBe('entering')

    // Register the element after showLayer
    orchestrator.registerLayer(priority, mockElement)

    // Wait for any animations to complete
    await testUtils.waitFor(() => false, 50) // Just wait 50ms

    // BUG: State is still 'entering' because no animation was triggered
    expect(orchestrator.getLayerState(priority)).toBe('entering')
    // It should be 'active' but it's stuck!
  })

  test('NORMAL FLOW: registration before showLayer works correctly', async () => {
    // This test shows the normal flow works fine
    const priority: LayerPriority = 'background'
    const content = { type: 'test-content' }

    // Register element FIRST (normal flow)
    orchestrator.registerLayer(priority, mockElement)

    // Then call showLayer
    orchestrator.showLayer(priority, content)

    // Should be entering
    expect(orchestrator.getLayerState(priority)).toBe('entering')

    // Wait for animation to complete
    await testUtils.waitFor(() => {
      return orchestrator.getLayerState(priority) === 'active'
    }, 100)

    // Should reach active state
    expect(orchestrator.getLayerState(priority)).toBe('active')
  })

  test('BUG CONFIRMED: Element registration has no effect on stuck state', async () => {
    const priority: LayerPriority = 'background'
    const content = { type: 'test-content' }

    // Trigger race condition
    orchestrator.showLayer(priority, content)
    expect(orchestrator.getLayerState(priority)).toBe('entering')

    // Register element later
    orchestrator.registerLayer(priority, mockElement)

    // Wait longer to see if anything changes
    await testUtils.waitFor(() => false, 200)

    // State is still stuck at 'entering' - this confirms the bug
    expect(orchestrator.getLayerState(priority)).toBe('entering')
    
    // The fix should make this test pass by reaching 'active'
  })
})