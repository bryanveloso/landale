/**
 * Environment Detection Utility
 *
 * Simple, synchronous environment detection for Landale.
 * Detects: development, production, OBS browser source, and Tauri app.
 */

export type Environment = 'development' | 'production' | 'obs' | 'tauri'

/**
 * Detect the current runtime environment
 *
 * Priority order:
 * 1. OBS Browser Source (window.obsstudio)
 * 2. Tauri App (window.__TAURI__)
 * 3. Development (localhost)
 * 4. Production (default)
 */
export function detectEnvironment(): Environment {
  // Only available in browser context
  if (typeof window !== 'undefined') {
    // Check for OBS Browser Source first
    if ('obsstudio' in window && window.obsstudio) {
      return 'obs'
    }

    // Check for Tauri app
    if ('__TAURI__' in window && window.__TAURI__) {
      return 'tauri'
    }

    // Check for development environment
    if (
      window.location.hostname === 'localhost' ||
      window.location.hostname === '127.0.0.1' ||
      window.location.hostname.startsWith('192.168.') ||
      window.location.hostname.startsWith('10.')
    ) {
      return 'development'
    }
  }

  // Default to production for any other case
  // (including server-side contexts)
  return 'production'
}

// Export a constant for easy access
export const currentEnvironment = detectEnvironment()
