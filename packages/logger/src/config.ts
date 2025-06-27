import { z } from 'zod'

// Log level schema
export const LogLevelSchema = z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
export type LogLevel = z.infer<typeof LogLevelSchema>

// Logger configuration schema
export const LoggerConfigSchema = z.object({
  // Basic configuration
  level: LogLevelSchema.default('info'),
  pretty: z.boolean().default(false),
  
  // Service identification
  service: z.string(),
  version: z.string().optional(),
  environment: z.string().default('development'),
  
  // Output formatting
  timestamp: z.boolean().default(true),
  includeStackTrace: z.boolean().default(true),
  
  // Performance
  sampleRate: z.number().min(0).max(1).default(1), // For high-volume logs
  
  // Redaction patterns for sensitive data
  redact: z.array(z.string()).default([
    'password',
    'token',
    'secret',
    'authorization',
    'cookie',
    'sessionId',
    'apiKey',
    'clientSecret'
  ]),
  
  // Context fields to include in every log
  defaultMeta: z.record(z.unknown()).optional()
})

export type LoggerConfig = z.infer<typeof LoggerConfigSchema>

// Environment-based configuration helper
export function getLoggerConfig(overrides: Partial<LoggerConfig> = {}): LoggerConfig {
  const env = process.env.NODE_ENV || 'development'
  const isDev = env === 'development'
  
  return LoggerConfigSchema.parse({
    level: process.env.LOG_LEVEL || (isDev ? 'debug' : 'info'),
    pretty: process.env.STRUCTURED_LOGGING !== 'true' && isDev,
    environment: env,
    service: overrides.service || 'unknown',
    ...overrides
  })
}

// Standard log fields for consistency
export interface LogContext {
  // Request context
  correlationId?: string
  requestId?: string
  userId?: string
  sessionId?: string
  
  // Operation context
  operation?: string
  duration?: number
  status?: 'success' | 'failure'
  
  // Error context
  error?: {
    message: string
    stack?: string
    code?: string
    type?: string
    cause?: unknown
  }
  
  // Performance context
  performance?: {
    memory?: NodeJS.MemoryUsage
    duration?: number
    count?: number
  }
  
  // Custom metadata
  metadata?: Record<string, unknown>
}

// Standard error serializer
export function serializeError(error: unknown): LogContext['error'] {
  if (error instanceof Error) {
    return {
      message: error.message,
      stack: error.stack,
      type: error.constructor.name,
      code: (error as any).code,
      cause: (error as any).cause
    }
  }
  
  return {
    message: String(error),
    type: typeof error
  }
}

// Performance helper
export function measurePerformance(start: number): LogContext['performance'] {
  return {
    duration: Date.now() - start,
    memory: process.memoryUsage()
  }
}