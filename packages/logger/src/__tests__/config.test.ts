import { describe, test, expect } from 'bun:test'
import { LoggerConfigSchema, LogLevelSchema, getLoggerConfig, serializeError } from '../config'

describe('Logger Configuration', () => {
  describe('LogLevelSchema', () => {
    test('accepts valid log levels', () => {
      const validLevels = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']

      validLevels.forEach((level) => {
        const result = LogLevelSchema.safeParse(level)
        expect(result.success).toBe(true)
        if (result.success) {
          expect(result.data).toBe(level)
        }
      })
    })

    test('rejects invalid log levels', () => {
      const invalidLevels = ['verbose', 'critical', 'notice', '', 'INFO', 'DEBUG']

      invalidLevels.forEach((level) => {
        const result = LogLevelSchema.safeParse(level)
        expect(result.success).toBe(false)
      })
    })
  })

  describe('LoggerConfigSchema', () => {
    test('accepts minimal valid configuration', () => {
      const config = {
        service: 'test-service'
      }

      const result = LoggerConfigSchema.safeParse(config)
      expect(result.success).toBe(true)

      if (result.success) {
        expect(result.data.service).toBe('test-service')
        expect(result.data.level).toBe('info') // default
        expect(result.data.environment).toBe('development') // default
        expect(result.data.timestamp).toBe(true) // default
      }
    })

    test('applies default values correctly', () => {
      const config = { service: 'test' }
      const result = LoggerConfigSchema.parse(config)

      expect(result.level).toBe('info')
      expect(result.pretty).toBe(false)
      expect(result.environment).toBe('development')
      expect(result.timestamp).toBe(true)
      expect(result.includeStackTrace).toBe(true)
      expect(result.sampleRate).toBe(1)
      expect(result.redact).toContain('password')
      expect(result.redact).toContain('token')
    })

    test('accepts full configuration', () => {
      const config = {
        service: 'landale-overlays',
        version: '1.0.0',
        environment: 'production',
        level: 'warn' as const,
        pretty: true,
        timestamp: false,
        includeStackTrace: false,
        sampleRate: 0.5,
        redact: ['custom-field'],
        defaultMeta: { datacenter: 'us-east-1' }
      }

      const result = LoggerConfigSchema.safeParse(config)
      expect(result.success).toBe(true)

      if (result.success) {
        expect(result.data.service).toBe('landale-overlays')
        expect(result.data.level).toBe('warn')
        expect(result.data.pretty).toBe(true)
        expect(result.data.sampleRate).toBe(0.5)
        expect(result.data.redact).toEqual(['custom-field'])
        expect(result.data.defaultMeta?.datacenter).toBe('us-east-1')
      }
    })

    test('validates sample rate boundaries', () => {
      const validSampleRates = [0, 0.5, 1]
      const invalidSampleRates = [-0.1, 1.1, 2]

      validSampleRates.forEach((rate) => {
        const config = { service: 'test', sampleRate: rate }
        const result = LoggerConfigSchema.safeParse(config)
        expect(result.success).toBe(true)
      })

      invalidSampleRates.forEach((rate) => {
        const config = { service: 'test', sampleRate: rate }
        const result = LoggerConfigSchema.safeParse(config)
        expect(result.success).toBe(false)
      })
    })

    test('requires service field', () => {
      const config = { level: 'info' }
      const result = LoggerConfigSchema.safeParse(config)
      expect(result.success).toBe(false)
    })

    test('validates redact array contains strings', () => {
      const validConfig = {
        service: 'test',
        redact: ['field1', 'field2']
      }
      const invalidConfig = {
        service: 'test',
        redact: ['field1', 123, 'field2'] // mixed types
      }

      expect(LoggerConfigSchema.safeParse(validConfig).success).toBe(true)
      expect(LoggerConfigSchema.safeParse(invalidConfig).success).toBe(false)
    })
  })

  describe('getLoggerConfig', () => {
    test('merges partial config with defaults', () => {
      const partialConfig = {
        service: 'test-service',
        level: 'debug' as const
      }

      const result = getLoggerConfig(partialConfig)

      expect(result.service).toBe('test-service')
      expect(result.level).toBe('debug')
      expect(result.environment).toBeDefined() // Uses NODE_ENV or 'development'
      expect(result.timestamp).toBe(true) // default
    })

    test('preserves all provided config values', () => {
      const fullConfig = {
        service: 'custom-service',
        version: '2.0.0',
        environment: 'staging',
        level: 'error' as const,
        pretty: true,
        timestamp: false,
        includeStackTrace: false,
        sampleRate: 0.8,
        redact: ['sensitive-data'],
        defaultMeta: { region: 'eu-west-1' }
      }

      const result = getLoggerConfig(fullConfig)

      expect(result).toEqual(fullConfig)
    })

    test('handles empty config object', () => {
      const result = getLoggerConfig({})
      expect(result.service).toBe('unknown') // Default fallback
      expect(result.environment).toBeDefined()
    })

    test('validates config during merge', () => {
      const invalidConfig = {
        service: 'test',
        level: 'invalid-level' as unknown
      }

      expect(() => getLoggerConfig(invalidConfig as Parameters<typeof getLoggerConfig>[0])).toThrow()
    })
  })

  describe('serializeError', () => {
    test('serializes standard Error objects', () => {
      const error = new Error('Test error message')
      const serialized = serializeError(error)

      expect(serialized.message).toBe('Test error message')
      expect(serialized.type).toBe('Error')
      expect(serialized.stack).toBeDefined()
      expect(typeof serialized.stack).toBe('string')
    })

    test('serializes custom Error types', () => {
      class CustomError extends Error {
        constructor(
          message: string,
          public code: string
        ) {
          super(message)
          this.name = 'CustomError'
        }
      }

      const error = new CustomError('Custom error', '404')
      const serialized = serializeError(error)

      expect(serialized.message).toBe('Custom error')
      expect(serialized.type).toBe('CustomError')
      expect(serialized.code).toBe('404')
    })

    test('handles Error objects with additional properties', () => {
      const error = new Error('Test error') as Error & { code?: string }
      // Add custom properties
      error.code = '500'

      const serialized = serializeError(error)

      expect(serialized.message).toBe('Test error')
      expect(serialized.code).toBe('500')
      expect(serialized.type).toBe('Error')
    })

    test('handles undefined and null errors gracefully', () => {
      expect(serializeError(undefined as unknown)).toEqual({
        message: 'undefined',
        type: 'undefined'
      })
      expect(serializeError(null as unknown)).toEqual({
        message: 'null',
        type: 'object'
      })
    })

    test('handles non-Error objects', () => {
      const nonError = { message: 'Not an error', data: 'test' }
      const serialized = serializeError(nonError as unknown)

      expect(serialized.message).toBe('[object Object]')
      expect(serialized.type).toBe('object')
    })

    test('handles circular references in error objects', () => {
      const error = new Error('Circular error')
      const circular: Record<string, unknown> = { error }
      circular.self = circular
      ;(error as Error & { circular?: unknown }).circular = circular

      // Should not throw even with circular references
      expect(() => serializeError(error)).not.toThrow()

      const serialized = serializeError(error)
      expect(serialized.message).toBe('Circular error')
      // Circular references should be handled (exact behavior depends on implementation)
    })

    test('preserves error stack traces', () => {
      function createNestedError() {
        function level2() {
          function level3() {
            throw new Error('Deep error')
          }
          return level3()
        }
        return level2()
      }

      try {
        createNestedError()
      } catch (error) {
        const serialized = serializeError(error as Error)

        expect(serialized.stack).toBeDefined()
        expect(serialized.stack).toContain('Deep error')
        expect(serialized.stack).toContain('level3')
      }
    })
  })

  describe('Configuration Edge Cases', () => {
    test('handles extreme sample rates', () => {
      const configs = [
        { service: 'test', sampleRate: 0 }, // No logging
        { service: 'test', sampleRate: 1 }, // All logging
        { service: 'test', sampleRate: 0.001 }, // Very low
        { service: 'test', sampleRate: 0.999 } // Very high
      ]

      configs.forEach((config) => {
        const result = LoggerConfigSchema.safeParse(config)
        expect(result.success).toBe(true)
      })
    })

    test('handles empty and whitespace service names', () => {
      const invalidServices = ['', '   ', '\t', '\n']

      invalidServices.forEach((service) => {
        const result = LoggerConfigSchema.safeParse({ service })
        expect(result.success).toBe(false)
      })
    })

    test('handles large redact arrays', () => {
      const largeRedactArray = Array.from({ length: 1000 }, (_, i) => `field${i}`)
      const config = { service: 'test', redact: largeRedactArray }

      const result = LoggerConfigSchema.safeParse(config)
      expect(result.success).toBe(true)
      if (result.success) {
        expect(result.data.redact.length).toBe(1000)
      }
    })

    test('handles complex defaultMeta objects', () => {
      const complexMeta = {
        nested: {
          deep: {
            value: 'test'
          },
          array: [1, 2, 3],
          null_value: null,
          boolean: true
        },
        timestamp: new Date().toISOString(),
        number: 42
      }

      const config = { service: 'test', defaultMeta: complexMeta }
      const result = LoggerConfigSchema.safeParse(config)

      expect(result.success).toBe(true)
      if (result.success) {
        expect(result.data.defaultMeta).toEqual(complexMeta)
      }
    })
  })
})
