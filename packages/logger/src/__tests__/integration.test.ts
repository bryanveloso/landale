import { describe, test, expect } from 'bun:test'
import { createLogger } from '../index'

describe('Logger Integration', () => {
  test('createLogger creates a functional logger instance', () => {
    const logger = createLogger({ service: 'test-service' })

    expect(logger).toBeDefined()
    expect(typeof logger.info).toBe('function')
    expect(typeof logger.error).toBe('function')
    expect(typeof logger.warn).toBe('function')
    expect(typeof logger.debug).toBe('function')
    expect(typeof logger.trace).toBe('function')
    expect(typeof logger.fatal).toBe('function')
    expect(typeof logger.child).toBe('function')
    expect(typeof logger.time).toBe('function')
    expect(typeof logger.measure).toBe('function')
    expect(typeof logger.measureAsync).toBe('function')
  })

  test('logger child method creates child logger', () => {
    const logger = createLogger({ service: 'test-service' })
    const child = logger.child({ module: 'auth' })

    expect(child).toBeDefined()
    expect(typeof child.info).toBe('function')
    expect(child).not.toBe(logger) // Should be a different instance
  })

  test('logger methods do not throw with various inputs', () => {
    const logger = createLogger({ service: 'test-service' })

    expect(() => {
      logger.info('Simple message')
      logger.error('Error message', { error: new Error('Test') })
      logger.debug('Debug with context', { userId: '123', data: { nested: true } })
      logger.warn('Warning with null', { value: null })
      logger.trace('Trace with undefined', { value: undefined })
    }).not.toThrow()
  })

  test('measure method returns result and does not throw', () => {
    const logger = createLogger({ service: 'test-service' })

    const result = logger.measure('test-operation', () => {
      return 'operation-result'
    })

    expect(result).toBe('operation-result')
  })

  test('measureAsync method returns promise result and does not throw', async () => {
    const logger = createLogger({ service: 'test-service' })

    const result = await logger.measureAsync('async-operation', async () => {
      await new Promise((resolve) => setTimeout(resolve, 1))
      return 'async-result'
    })

    expect(result).toBe('async-result')
  })

  test('time method returns a function', () => {
    const logger = createLogger({ service: 'test-service' })

    const endTimer = logger.time('timer-test')
    expect(typeof endTimer).toBe('function')

    // Should not throw when called
    expect(() => endTimer()).not.toThrow()
  })

  test('logger works with complex configuration', () => {
    const logger = createLogger({
      service: 'complex-service',
      level: 'warn',
      version: '1.0.0',
      environment: 'test',
      redact: ['password', 'secret'],
      defaultMeta: { datacenter: 'us-east-1' }
    })

    expect(logger).toBeDefined()

    // Should not throw with redacted fields
    expect(() => {
      logger.warn('Test with sensitive data', {
        password: 'should-be-hidden',
        secret: 'also-hidden',
        safeData: 'visible'
      })
    }).not.toThrow()
  })

  test('logger handles error objects properly', () => {
    const logger = createLogger({ service: 'error-test' })

    const testError = new Error('Test error')
    testError.stack = 'Test stack trace'

    expect(() => {
      logger.error('Error occurred', { error: testError })
    }).not.toThrow()
  })

  test('logger level filtering works in configuration', () => {
    // This test just ensures the logger can be created with different levels
    const levels = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'] as const

    levels.forEach((level) => {
      expect(() => {
        const logger = createLogger({ service: 'level-test', level })
        logger.info('Test message')
      }).not.toThrow()
    })
  })
})
