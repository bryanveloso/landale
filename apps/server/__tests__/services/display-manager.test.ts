import { describe, it, expect, beforeEach, vi } from 'vitest'
import { z } from 'zod'
import { DisplayManager } from '@/services/display-manager'
import { eventEmitter } from '@/events'

// Mock the event emitter
vi.mock('@/events', () => ({
  eventEmitter: {
    emit: vi.fn()
  }
}))

describe('DisplayManager', () => {
  let displayManager: DisplayManager

  beforeEach(() => {
    displayManager = new DisplayManager()
    vi.clearAllMocks()
  })

  describe('register', () => {
    it('should register a display with valid schema and data', () => {
      const schema = z.object({
        text: z.string(),
        isVisible: z.boolean()
      })
      const defaultData = { text: 'Hello', isVisible: true }

      displayManager.register('testDisplay', schema, defaultData)

      const display = displayManager.get('testDisplay')
      expect(display).toBeDefined()
      expect(display.id).toBe('testDisplay')
      expect(display.data).toEqual(defaultData)
    })

    it('should not overwrite when registering duplicate display', () => {
      const schema = z.object({ value: z.number() })

      displayManager.register('duplicate', schema, { value: 1 })
      displayManager.register('duplicate', schema, { value: 2 })

      // Should keep the first value
      const display = displayManager.get('duplicate')
      expect(display?.data.value).toBe(1)
    })

    it('should validate default data against schema', () => {
      const schema = z.object({
        count: z.number().min(0)
      })

      expect(() => {
        displayManager.register('invalid', schema, { count: -1 })
      }).toThrow()
    })
  })

  describe('update', () => {
    it('should update display data and emit event', () => {
      const schema = z.object({
        count: z.number(),
        label: z.string()
      })
      const initialData = { count: 0, label: 'Test' }

      displayManager.register('counter', schema, initialData)
      displayManager.update('counter', { count: 5 })

      const display = displayManager.get('counter')
      expect(display.data.count).toBe(5)
      expect(display.data.label).toBe('Test') // Unchanged
      expect(eventEmitter.emit).toHaveBeenCalledWith('display:counter:update', display)
    })

    it('should validate updates against schema', () => {
      const schema = z.object({
        value: z.number().positive()
      })

      displayManager.register('positive', schema, { value: 1 })

      expect(() => {
        displayManager.update('positive', { value: -5 })
      }).toThrow()
    })

    it('should handle partial updates', () => {
      const schema = z.object({
        x: z.number(),
        y: z.number(),
        label: z.string()
      })

      displayManager.register('position', schema, { x: 0, y: 0, label: 'Origin' })
      displayManager.update('position', { x: 10 })

      const display = displayManager.get('position')
      expect(display.data).toEqual({ x: 10, y: 0, label: 'Origin' })
    })
  })

  describe('get', () => {
    it('should return undefined for non-existent display', () => {
      const result = displayManager.get('nonexistent')
      expect(result).toBeUndefined()
    })
  })

  describe('getData', () => {
    it('should throw error for non-existent display', () => {
      expect(() => {
        displayManager.getData('nonexistent')
      }).toThrow('Display nonexistent not found')
    })
  })

  describe('list', () => {
    it('should return all registered displays', () => {
      const schema1 = z.object({ value: z.number() })
      const schema2 = z.object({ text: z.string() })

      displayManager.register('display1', schema1, { value: 1 })
      displayManager.register('display2', schema2, { text: 'test' })

      const displays = displayManager.list()
      expect(displays).toHaveLength(2)
      expect(displays.map((d) => d.id)).toContain('display1')
      expect(displays.map((d) => d.id)).toContain('display2')
    })
  })
})
