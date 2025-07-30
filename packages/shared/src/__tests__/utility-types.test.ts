import { describe, test, expect } from 'bun:test'
import type { DeepPartial, Nullable } from '../index'

describe('Utility Types', () => {
  describe('DeepPartial', () => {
    interface TestInterface {
      name: string
      settings: {
        enabled: boolean
        config: {
          timeout: number
          retries: number
        }
      }
      tags: string[]
    }

    test('DeepPartial makes all properties optional', () => {
      // This test validates type behavior at compile time
      const partial: DeepPartial<TestInterface> = {}
      expect(partial).toBeDefined()

      const partialWithSome: DeepPartial<TestInterface> = {
        name: 'test'
      }
      expect(partialWithSome.name).toBe('test')

      const partialNested: DeepPartial<TestInterface> = {
        settings: {
          enabled: true
        }
      }
      expect(partialNested.settings?.enabled).toBe(true)

      const partialDeepNested: DeepPartial<TestInterface> = {
        settings: {
          config: {
            timeout: 5000
          }
        }
      }
      expect(partialDeepNested.settings?.config?.timeout).toBe(5000)
    })

    test('DeepPartial preserves primitive types', () => {
      interface PrimitiveTest {
        str: string
        num: number
        bool: boolean
        date: Date
      }

      const partial: DeepPartial<PrimitiveTest> = {
        str: 'test',
        num: 42
      }

      expect(typeof partial.str).toBe('string')
      expect(typeof partial.num).toBe('number')
      expect(partial.bool).toBeUndefined()
      expect(partial.date).toBeUndefined()
    })

    test('DeepPartial works with arrays', () => {
      interface ArrayTest {
        items: Array<{
          id: number
          name: string
        }>
      }

      const partial: DeepPartial<ArrayTest> = {
        items: [{ id: 1 }]
      }

      expect(Array.isArray(partial.items)).toBe(true)
      expect(partial.items?.[0]?.id).toBe(1)
      expect(partial.items?.[0]?.name).toBeUndefined()
    })
  })

  describe('Nullable', () => {
    test('Nullable allows null and undefined', () => {
      const nullableString: Nullable<string> = null
      const undefinedString: Nullable<string> = undefined
      const validString: Nullable<string> = 'hello'

      expect(nullableString).toBeNull()
      expect(undefinedString).toBeUndefined()
      expect(validString).toBe('hello')
    })

    test('Nullable works with complex types', () => {
      interface ComplexType {
        data: {
          value: number
        }
      }

      const nullableComplex: Nullable<ComplexType> = null
      const validComplex: Nullable<ComplexType> = {
        data: { value: 42 }
      }

      expect(nullableComplex).toBeNull()
      expect(validComplex?.data.value).toBe(42)
    })

    test('Nullable preserves type checking', () => {
      const nullableNumber: Nullable<number> = 42

      if (nullableNumber !== null && nullableNumber !== undefined) {
        // TypeScript should know this is a number now
        expect(typeof nullableNumber).toBe('number')
        expect(nullableNumber.toFixed).toBeDefined()
      }
    })
  })

  describe('Type Integration', () => {
    test('DeepPartial and Nullable can be combined', () => {
      interface TestType {
        config: {
          setting: string
        }
      }

      const combined: Nullable<DeepPartial<TestType>> = {
        config: {}
      }

      expect(combined).toBeDefined()
      expect(combined?.config).toBeDefined()
      expect(combined?.config?.setting).toBeUndefined()
    })

    test('Types work with real-world usage patterns', () => {
      interface StreamConfig {
        server: {
          host: string
          port: number
          ssl: boolean
        }
        features: {
          chat: boolean
          emotes: boolean
          alerts: {
            enabled: boolean
            types: string[]
          }
        }
      }

      // Partial update pattern
      const update: DeepPartial<StreamConfig> = {
        server: {
          port: 8080
        },
        features: {
          alerts: {
            enabled: false
          }
        }
      }

      expect(update.server?.port).toBe(8080)
      expect(update.server?.host).toBeUndefined()
      expect(update.features?.alerts?.enabled).toBe(false)
      expect(update.features?.alerts?.types).toBeUndefined()

      // Nullable state pattern
      const state: Nullable<StreamConfig> = null
      expect(state).toBeNull()

      const initializedState: Nullable<StreamConfig> = {
        server: {
          host: 'localhost',
          port: 7175,
          ssl: false
        },
        features: {
          chat: true,
          emotes: true,
          alerts: {
            enabled: true,
            types: ['follow', 'sub', 'cheer']
          }
        }
      }

      expect(initializedState?.server.host).toBe('localhost')
      expect(initializedState?.features.alerts.types).toContain('follow')
    })
  })
})
