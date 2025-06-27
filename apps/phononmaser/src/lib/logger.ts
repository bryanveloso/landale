import { createLogger } from '@landale/logger'

// Create the main logger instance
export const logger = createLogger({
  service: 'landale-phononmaser',
  version: '0.1.0'
})

// Create module-specific loggers
export const wsLogger = logger.child({ module: 'websocket' })
export const audioLogger = logger.child({ module: 'audio-processor' })
export const whisperLogger = logger.child({ module: 'whisper' })
export const lmLogger = logger.child({ module: 'lm-studio' })
