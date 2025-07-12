/**
 * Simple performance monitoring for development
 * Uses console.time for minimal overhead and standard debugging
 */

// Only enable in development using Vite standard detection
const isDev = import.meta?.env?.DEV ?? false

export class PerformanceMonitor {
  /**
   * Track a layer resolution operation using console.time
   */
  static trackLayerResolution<T>(operation: () => T): T {
    if (!isDev) return operation()

    console.time('Layer Resolution')
    const result = operation()
    console.timeEnd('Layer Resolution')

    return result
  }

  /**
   * Track a render cycle with simple console log
   */
  static trackRenderCycle(): void {
    if (!isDev) return
    console.debug('🔄 Render cycle triggered')
  }

  /**
   * Measure any operation with console.time
   */
  static measure<T>(label: string, operation: () => T): T {
    if (!isDev) return operation()

    console.time(label)
    const result = operation()
    console.timeEnd(label)

    return result
  }

  /**
   * Simple performance logging for debugging
   */
  static log(message: string, data?: Record<string, unknown>): void {
    if (!isDev) return
    console.debug(`⚡ ${message}`, data)
  }
}