import pino from 'pino'
import {
  type Logger,
  type LoggerConfig,
  type LogContext,
  type LogLevel,
  getLoggerConfig,
  serializeError
} from './config'

export * from './config'

// Custom log method types
type LogMethod = (message: string, context?: LogContext) => void
type ChildLoggerOptions = {
  module?: string
  correlationId?: string
  [key: string]: unknown
}

// Create base Pino logger with configuration
function createPinoLogger(config: LoggerConfig): pino.Logger {
  const redactPaths = config.redact.map((field) => `*.${field}`)

  const pinoConfig: pino.LoggerOptions = {
    level: config.level,
    base: {
      service: config.service,
      version: config.version,
      env: config.environment,
      pid: process.pid,
      hostname: undefined, // Remove hostname for privacy
      ...config.defaultMeta
    },
    timestamp: config.timestamp ? pino.stdTimeFunctions.isoTime : false,
    formatters: {
      level: (label) => ({ level: label }),
      bindings: (bindings) => ({
        ...bindings,
        hostname: undefined // Remove hostname from bindings
      })
    },
    serializers: {
      error: serializeError,
      err: serializeError
    },
    redact: {
      paths: redactPaths,
      censor: '[REDACTED]'
    }
  }

  // Add pretty printing in development
  if (config.pretty) {
    return pino({
      ...pinoConfig,
      transport: {
        target: 'pino-pretty',
        options: {
          colorize: true,
          translateTime: 'HH:MM:ss',
          ignore: 'pid,hostname',
          messageFormat: '{service} | {module} | {msg}',
          errorLikeObjectKeys: ['err', 'error']
        }
      }
    })
  }

  return pino(pinoConfig)
}

// Wrap Pino logger with our interface
function wrapLogger(pinoLogger: pino.Logger, config: LoggerConfig): Logger {
  const timers = new Map<string, number>()

  // Sample rate check
  const shouldLog = () => Math.random() <= config.sampleRate

  // Create log method
  const createLogMethod = (level: LogLevel): LogMethod => {
    return (message: string, context?: LogContext) => {
      if (!shouldLog()) return

      const logData: Record<string, unknown> = {}

      if (context) {
        // Add standard fields
        if (context.correlationId) logData.correlationId = context.correlationId
        if (context.requestId) logData.requestId = context.requestId
        if (context.userId) logData.userId = context.userId
        if (context.sessionId) logData.sessionId = context.sessionId
        if (context.operation) logData.operation = context.operation
        if (context.duration !== undefined) logData.duration = context.duration
        if (context.status) logData.status = context.status

        // Add error with proper serialization
        if (context.error) {
          logData.error = context.error
        }

        // Add performance metrics
        if (context.performance) {
          logData.performance = context.performance
        }

        // Add custom metadata
        if (context.metadata) {
          Object.assign(logData, context.metadata)
        }
      }

      pinoLogger[level](logData, message)
    }
  }

  return {
    fatal: createLogMethod('fatal'),
    error: createLogMethod('error'),
    warn: createLogMethod('warn'),
    info: createLogMethod('info'),
    debug: createLogMethod('debug'),
    trace: createLogMethod('trace'),

    child: (options: ChildLoggerOptions) => {
      const childPino = pinoLogger.child(options)
      return wrapLogger(childPino, config)
    },

    time: (label: string) => {
      const start = Date.now()
      timers.set(label, start)

      return () => {
        const duration = Date.now() - start
        timers.delete(label)
        pinoLogger.debug({ operation: label, duration }, `Operation completed: ${label}`)
      }
    },

    measure: <T>(label: string, fn: () => T): T => {
      const start = Date.now()
      try {
        const result = fn()
        const duration = Date.now() - start
        pinoLogger.debug({ operation: label, duration, status: 'success' }, `Operation completed: ${label}`)
        return result
      } catch (error) {
        const duration = Date.now() - start
        pinoLogger.error(
          {
            operation: label,
            duration,
            status: 'failure',
            error: serializeError(error)
          },
          `Operation failed: ${label}`
        )
        throw error
      }
    },

    measureAsync: async <T>(label: string, fn: () => Promise<T>): Promise<T> => {
      const start = Date.now()
      try {
        const result = await fn()
        const duration = Date.now() - start
        pinoLogger.debug({ operation: label, duration, status: 'success' }, `Operation completed: ${label}`)
        return result
      } catch (error) {
        const duration = Date.now() - start
        pinoLogger.error(
          {
            operation: label,
            duration,
            status: 'failure',
            error: serializeError(error)
          },
          `Operation failed: ${label}`
        )
        throw error
      }
    }
  }
}

// Main factory function
export function createLogger(config: Partial<LoggerConfig> & { service: string }): Logger {
  const fullConfig = getLoggerConfig(config)
  const pinoLogger = createPinoLogger(fullConfig)
  return wrapLogger(pinoLogger, fullConfig)
}

// Create logger with Seq transport
export function createLoggerWithSeq(
  config: Partial<LoggerConfig> & { service: string },
  seqUrl: string,
  seqApiKey?: string
): Logger {
  const fullConfig = getLoggerConfig(config)
  
  // Create Pino logger with Seq transport
  const pinoLogger = pino({
    ...createPinoOptions(fullConfig),
    transport: {
      targets: [
        {
          target: 'pino/file',
          options: { destination: 1 } // stdout
        },
        {
          target: new URL('./seq-transport.ts', import.meta.url).href,
          options: {
            serverUrl: seqUrl,
            apiKey: seqApiKey,
            batchSize: 100,
            flushInterval: 1000
          }
        }
      ]
    }
  })
  
  return wrapLogger(pinoLogger, fullConfig)
}

// Helper to extract pino options from createPinoLogger
function createPinoOptions(config: LoggerConfig): pino.LoggerOptions {
  const redactPaths = config.redact.map((field) => `*.${field}`)
  
  return {
    level: config.level,
    base: {
      service: config.service,
      version: config.version,
      env: config.environment,
      pid: process.pid,
      hostname: undefined,
      ...config.defaultMeta
    },
    timestamp: config.timestamp ? pino.stdTimeFunctions.isoTime : false,
    formatters: {
      level: (label) => ({ level: label }),
      bindings: (bindings) => ({
        ...bindings,
        hostname: undefined
      })
    },
    serializers: {
      error: serializeError,
      err: serializeError
    },
    redact: {
      paths: redactPaths,
      censor: '[REDACTED]'
    }
  }
}

// Correlation ID generator
export function generateCorrelationId(): string {
  return `${Date.now().toString()}-${Math.random().toString(36).substring(2, 11)}`
}

// Request context helper
export function createRequestContext(): LogContext {
  return {
    correlationId: generateCorrelationId(),
    requestId: generateCorrelationId()
  }
}
