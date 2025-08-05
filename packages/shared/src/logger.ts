/**
 * Environment-aware logger utility for frontend services.
 *
 * Debug logs are automatically stripped in production builds.
 * Use this instead of console.log to ensure proper log levels
 * and prevent sensitive data leakage in production.
 */

const isDev = typeof import.meta !== 'undefined' ? import.meta.env?.DEV : process.env.NODE_ENV === 'development'

export const logger = {
  /**
   * Debug level - development only
   * Use for detailed debugging information
   */
  debug: (...args: unknown[]) => {
    if (isDev) {
      console.log('[DEBUG]', ...args)
    }
  },

  /**
   * Info level - important state changes
   * Use for service starts, connections established, etc.
   */
  info: (...args: unknown[]) => {
    console.info('[INFO]', ...args)
  },

  /**
   * Warning level - recoverable errors
   * Use for retries, fallbacks, degraded functionality
   */
  warn: (...args: unknown[]) => {
    console.warn('[WARN]', ...args)
  },

  /**
   * Error level - unrecoverable errors
   * Use for failures that require user intervention
   */
  error: (...args: unknown[]) => {
    console.error('[ERROR]', ...args)
  }
}
