import { createLogger, trackPerformance } from '@landale/logger/browser'

// Create the main logger for overlays
export const logger = createLogger({
  service: 'landale-overlays',
  level: import.meta.env.DEV ? 'debug' : 'info',
  enableConsole: true,
  sampleRate: 1,
  // Optional: Send logs to server in production
  endpoint: import.meta.env.PROD ? '/api/logs' : undefined,
  bufferSize: 50,
  flushInterval: 10000 // 10 seconds
})

// Enable automatic performance and error tracking
if (typeof window !== 'undefined') {
  trackPerformance(logger)
}

// Create module-specific loggers
export const wsLogger = logger.child({ module: 'websocket' })
export const animationLogger = logger.child({ module: 'animation' })
export const emoteLogger = logger.child({ module: 'emotes' })
export const gameLogger = logger.child({ module: 'game' })
