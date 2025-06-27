# @landale/logger

Centralized logging package for Landale services with best practices built-in.

## Features

- **Structured logging** with Pino for high performance
- **Browser support** with batching and remote logging
- **Automatic redaction** of sensitive fields
- **Correlation IDs** for request tracking
- **Performance measurement** helpers
- **Error serialization** with stack traces
- **Sample rate control** for high-volume scenarios
- **Pretty printing** for development
- **TypeScript** with full type safety

## Usage

### Server-side (Node/Bun)

```typescript
import { createLogger } from '@landale/logger'

const logger = createLogger({
  service: 'landale-server',
  version: '1.0.0'
})

// Basic logging
logger.info('Server started', {
  metadata: { port: 3000 }
})

// Error logging with automatic serialization
try {
  await someOperation()
} catch (error) {
  logger.error('Operation failed', {
    error: error,
    operation: 'someOperation'
  })
}

// Performance measurement
const result = await logger.measureAsync('database-query', async () => {
  return await db.query('SELECT * FROM users')
})

// Child logger for modules
const dbLogger = logger.child({ module: 'database' })
dbLogger.debug('Query executed')
```

### Browser-side

```typescript
import { createLogger, trackPerformance } from '@landale/logger/browser'

const logger = createLogger({
  service: 'landale-overlays',
  endpoint: '/api/logs', // Optional remote logging
  level: 'debug',
  bufferSize: 50
})

// Enable automatic performance and error tracking
trackPerformance(logger)

// Use same interface as server
logger.info('Overlay loaded')
logger.error('WebSocket connection failed', {
  error: { message: 'Connection refused' }
})
```

## Configuration

### Environment Variables

- `LOG_LEVEL` - Minimum log level (default: 'info', 'debug' in development)
- `NODE_ENV` - Environment name (development/production)
- `STRUCTURED_LOGGING` - Force JSON output (default: false)

### Log Levels

From highest to lowest priority:

- `fatal` - System is unusable
- `error` - Error conditions
- `warn` - Warning conditions
- `info` - Informational messages
- `debug` - Debug-level messages
- `trace` - Trace-level messages

### Standard Fields

Every log entry includes:

- `timestamp` - ISO 8601 timestamp
- `level` - Log level
- `service` - Service name
- `message` - Log message
- `correlationId` - Request correlation ID (if provided)
- `requestId` - Individual request ID (if provided)
- `userId` - User identifier (if provided)
- `operation` - Operation name (if provided)
- `duration` - Operation duration in ms (if provided)
- `error` - Serialized error object (if provided)

## Best Practices

1. **Use structured data** instead of string concatenation
2. **Include correlation IDs** for request tracking
3. **Use appropriate log levels** (don't log everything as 'info')
4. **Measure performance** of critical operations
5. **Handle errors properly** with full context
6. **Use child loggers** for module-specific logging
7. **Avoid logging sensitive data** (automatic redaction helps)
8. **Sample high-volume logs** to control costs

## Integration Examples

### tRPC Middleware

```typescript
export const loggingMiddleware = middleware(async ({ ctx, next, path }) => {
  const correlationId = generateCorrelationId()
  const logger = ctx.logger.child({
    correlationId,
    procedure: path
  })

  const result = await logger.measureAsync(path, () =>
    next({
      ctx: { ...ctx, logger, correlationId }
    })
  )

  return result
})
```

### WebSocket Handler

```typescript
wss.on('connection', (ws) => {
  const sessionId = generateCorrelationId()
  const wsLogger = logger.child({ sessionId, module: 'websocket' })

  wsLogger.info('Client connected')

  ws.on('error', (error) => {
    wsLogger.error('WebSocket error', { error })
  })

  ws.on('close', () => {
    wsLogger.info('Client disconnected')
  })
})
```
