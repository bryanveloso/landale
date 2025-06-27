import { describe, it, expect, beforeEach, spyOn, type Mock } from 'bun:test'
import { z } from 'zod'
import { DisplayManager } from '@/services/display-manager'
import * as events from '@/events'

describe('DisplayManager', () => {
  let displayManager: DisplayManager
  let mockEmit: Mock<(event: string, data: unknown) => Promise<void>>

  beforeEach(() => {
    displayManager = new DisplayManager()

    // Spy on the eventEmitter.emit method
    mockEmit = spyOn(events.eventEmitter, 'emit').mockImplementation(() => Promise.resolve())
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
      expect(display?.id).toBe('testDisplay')
      expect(display?.data).toEqual(defaultData)
    })

    it('should not overwrite when registering duplicate display', () => {
      const schema = z.object({ value: z.number() })

      displayManager.register('duplicate', schema, { value: 1 })
      displayManager.register('duplicate', schema, { value: 2 })

      // Should keep the first value
      const display = displayManager.get('duplicate')
      expect((display?.data as { value: number }).value).toBe(1)
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
      expect(display?.data).toBeDefined()
      expect((display?.data as { count: number; label: string }).count).toBe(5)
      expect((display?.data as { count: number; label: string }).label).toBe('Test') // Unchanged
      expect(mockEmit).toHaveBeenCalledWith('display:counter:update', display)
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
      expect(display?.data).toEqual({ x: 10, y: 0, label: 'Origin' })
    })
  })

  describe('get', () => {
    it('should return undefined for non-existent display', () => {
      const result = displayManager.get('nonexistent')
      expect(result).toBeUndefined()
    })
  })

  describe('getData', () => {
    it('should return data for existing display', () => {
      const schema = z.object({ name: z.string() })
      displayManager.register('user', schema, { name: 'John' })

      const data = displayManager.getData('user')
      expect(data).toEqual({ name: 'John' })
    })

    it('should throw for non-existent display', () => {
      expect(() => {
        displayManager.getData('nonexistent')
      }).toThrow('Display nonexistent not found')
    })
  })
})
