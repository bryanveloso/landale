/**
 * Alert Prioritization Domain Tests - TypeScript/Client Side
 * TDD approach for pure alert prioritization business logic
 */

import { describe, test, expect } from 'bun:test'
import {
  getPriorityForAlertType,
  determineActiveAlert,
  sortAlertsByPriority,
  createAlert,
  getPriorityLevel,
  type Alert,
  type AlertType
} from './alert-prioritization'

describe('Alert Prioritization Domain - Client Side', () => {
  describe('getPriorityForAlertType', () => {
    test('returns high priority for alert type', () => {
      const priority = getPriorityForAlertType('alert')
      expect(priority).toBe(100)
    })

    test('returns medium priority for sub_train alert', () => {
      const priority = getPriorityForAlertType('sub_train')
      expect(priority).toBe(50)
    })

    test('returns low priority for ticker alert', () => {
      const priority = getPriorityForAlertType('ticker')
      expect(priority).toBe(10)
    })

    test('returns medium priority for manual_override alert', () => {
      const priority = getPriorityForAlertType('manual_override')
      expect(priority).toBe(50)
    })

    test('returns low priority for unknown alert types', () => {
      const priority = getPriorityForAlertType('unknown_type' as AlertType)
      expect(priority).toBe(10)
    })
  })

  describe('determineActiveAlert', () => {
    test('returns highest priority alert when available', () => {
      const interruptStack: Alert[] = [
        { type: 'ticker', priority: 10, data: {}, startedAt: '2024-01-01T00:00:01Z' },
        { type: 'alert', priority: 100, data: { message: 'Breaking' }, startedAt: '2024-01-01T00:00:02Z' },
        { type: 'sub_train', priority: 50, data: { count: 3 }, startedAt: '2024-01-01T00:00:03Z' }
      ]
      const tickerRotation: AlertType[] = ['emote_stats', 'recent_follows']

      const activeAlert = determineActiveAlert(interruptStack, tickerRotation)

      expect(activeAlert?.type).toBe('alert')
      expect(activeAlert?.priority).toBe(100)
    })

    test('returns FIFO for same priority alerts', () => {
      const interruptStack: Alert[] = [
        { type: 'alert', priority: 100, data: { message: 'Second' }, startedAt: '2024-01-01T00:00:02Z' },
        { type: 'alert', priority: 100, data: { message: 'First' }, startedAt: '2024-01-01T00:00:01Z' }
      ]
      const tickerRotation: AlertType[] = ['emote_stats']

      const activeAlert = determineActiveAlert(interruptStack, tickerRotation)

      expect(activeAlert?.type).toBe('alert')
      expect(activeAlert?.data.message).toBe('First')
    })

    test('falls back to ticker alert when no interrupts', () => {
      const interruptStack: Alert[] = []
      const tickerRotation: AlertType[] = ['emote_stats', 'recent_follows']

      const activeAlert = determineActiveAlert(interruptStack, tickerRotation)

      expect(activeAlert?.type).toBe('emote_stats')
      expect(activeAlert?.priority).toBe(10)
    })

    test('returns null when no interrupts and empty ticker rotation', () => {
      const interruptStack: Alert[] = []
      const tickerRotation: AlertType[] = []

      const activeAlert = determineActiveAlert(interruptStack, tickerRotation)

      expect(activeAlert).toBeNull()
    })

    test('ignores null interrupt stack entries', () => {
      const interruptStack: (Alert | null)[] = [
        null, 
        { type: 'sub_train', priority: 50, data: {}, startedAt: '2024-01-01T00:00:01Z' }
      ]
      const tickerRotation: AlertType[] = ['emote_stats']

      const activeAlert = determineActiveAlert(interruptStack, tickerRotation)

      expect(activeAlert?.type).toBe('sub_train')
      expect(activeAlert?.priority).toBe(50)
    })
  })

  describe('sortAlertsByPriority', () => {
    test('sorts alerts by priority descending', () => {
      const alertList: Alert[] = [
        { type: 'ticker', priority: 10, data: {}, startedAt: '2024-01-01T00:00:01Z' },
        { type: 'alert', priority: 100, data: {}, startedAt: '2024-01-01T00:00:02Z' },
        { type: 'sub_train', priority: 50, data: {}, startedAt: '2024-01-01T00:00:03Z' }
      ]

      const sorted = sortAlertsByPriority(alertList)

      const priorities = sorted.map(alert => alert.priority)
      expect(priorities).toEqual([100, 50, 10])
    })

    test('uses FIFO ordering for same priority items', () => {
      const alertList: Alert[] = [
        { type: 'alert', priority: 100, data: { message: 'Third' }, startedAt: '2024-01-01T00:00:03Z' },
        { type: 'alert', priority: 100, data: { message: 'First' }, startedAt: '2024-01-01T00:00:01Z' },
        { type: 'alert', priority: 100, data: { message: 'Second' }, startedAt: '2024-01-01T00:00:02Z' }
      ]

      const sorted = sortAlertsByPriority(alertList)

      const messages = sorted.map(alert => alert.data.message)
      expect(messages).toEqual(['First', 'Second', 'Third'])
    })

    test('handles alerts without startedAt timestamp', () => {
      const alertList: Alert[] = [
        { type: 'alert', priority: 100, data: {} },
        { type: 'sub_train', priority: 50, data: {}, startedAt: '2024-01-01T00:00:01Z' }
      ]

      const sorted = sortAlertsByPriority(alertList)

      // Should not crash and should prioritize by priority
      expect(sorted).toHaveLength(2)
      expect(sorted[0].priority).toBe(100)
    })

    test('handles empty alert list', () => {
      const sorted = sortAlertsByPriority([])
      expect(sorted).toEqual([])
    })
  })

  describe('createAlert', () => {
    test('creates alert with correct priority for alert type', () => {
      const alert = createAlert('alert', { message: 'Test' })

      expect(alert.type).toBe('alert')
      expect(alert.priority).toBe(100)
      expect(alert.data.message).toBe('Test')
      expect(typeof alert.id).toBe('string')
      expect(typeof alert.startedAt).toBe('string')
    })

    test('accepts custom ID option', () => {
      const alert = createAlert('sub_train', {}, { id: 'custom-123' })

      expect(alert.id).toBe('custom-123')
    })

    test('accepts custom duration option', () => {
      const alert = createAlert('alert', {}, { duration: 5000 })

      expect(alert.duration).toBe(5000)
    })

    test('generates unique IDs when not provided', () => {
      const alert1 = createAlert('alert', {})
      const alert2 = createAlert('alert', {})

      expect(alert1.id).not.toBe(alert2.id)
    })

    test('includes all required fields', () => {
      const alert = createAlert('manual_override', { action: 'test' })

      expect(alert).toHaveProperty('id')
      expect(alert).toHaveProperty('type')
      expect(alert).toHaveProperty('priority')
      expect(alert).toHaveProperty('data')
      expect(alert).toHaveProperty('duration')
      expect(alert).toHaveProperty('startedAt')
    })
  })

  describe('getPriorityLevel', () => {
    test('returns alert level when high priority alerts present in stack', () => {
      const interruptStack: Alert[] = [
        { type: 'emote_stats', priority: 10, data: {} },
        { type: 'alert', priority: 100, data: {} },
        { type: 'sub_train', priority: 50, data: {} }
      ]

      const level = getPriorityLevel(interruptStack)
      expect(level).toBe('alert')
    })

    test('returns sub_train level when sub trains present but no high priority alerts', () => {
      const interruptStack: Alert[] = [
        { type: 'emote_stats', priority: 10, data: {} },
        { type: 'sub_train', priority: 50, data: {} }
      ]

      const level = getPriorityLevel(interruptStack)
      expect(level).toBe('sub_train')
    })

    test('returns ticker level when only low priority alerts', () => {
      const interruptStack: Alert[] = [
        { type: 'emote_stats', priority: 10, data: {} },
        { type: 'recent_follows', priority: 10, data: {} }
      ]

      const level = getPriorityLevel(interruptStack)
      expect(level).toBe('ticker')
    })

    test('returns ticker level for empty interrupt stack', () => {
      const level = getPriorityLevel([])
      expect(level).toBe('ticker')
    })
  })
})