import { performance } from 'perf_hooks'
import { createLogger } from '@landale/logger'
import { eventEmitter } from '@/events'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'performance' })

export interface PerformanceMetric {
  operation: string
  duration: number
  success: boolean
  metadata?: Record<string, unknown>
  timestamp: Date
  correlationId?: string
}

export interface StreamHealthMetric {
  fps: number
  bitrate: number
  droppedFrames: number
  totalFrames: number
  cpuUsage: number
  memoryUsage: number
  congestion: number
  timestamp: Date
}

// Performance thresholds for alerts
const THRESHOLDS = {
  // OBS operations should complete quickly
  obsCall: {
    warning: 100, // ms
    critical: 500 // ms
  },
  // Database operations
  database: {
    warning: 50,
    critical: 200
  },
  // External API calls
  api: {
    warning: 500,
    critical: 2000
  },
  // WebSocket messages
  websocket: {
    warning: 50,
    critical: 200
  },
  // Stream health
  streamHealth: {
    fps: {
      warning: 25,
      critical: 20
    },
    droppedFramesPercent: {
      warning: 0.5,
      critical: 2.0
    },
    cpuUsage: {
      warning: 70,
      critical: 85
    }
  }
}

// Track recent metrics for analysis
const recentMetrics = new Map<string, PerformanceMetric[]>()
const METRICS_RETENTION = 5 * 60 * 1000 // 5 minutes

class PerformanceMonitor {
  private cleanupInterval: NodeJS.Timeout

  constructor() {
    // Clean up old metrics every minute
    this.cleanupInterval = setInterval(() => {
      this.cleanupMetrics()
    }, 60 * 1000)
  }

  private cleanupMetrics() {
    const cutoff = Date.now() - METRICS_RETENTION

    for (const [key, metrics] of recentMetrics.entries()) {
      const filtered = metrics.filter((m) => m.timestamp.getTime() > cutoff)
      if (filtered.length === 0) {
        recentMetrics.delete(key)
      } else {
        recentMetrics.set(key, filtered)
      }
    }
  }

  async trackOperation<T>(
    operation: string,
    category: 'obsCall' | 'database' | 'api' | 'websocket',
    fn: () => Promise<T>,
    metadata?: Record<string, unknown>
  ): Promise<T> {
    const start = performance.now()
    let success = true

    try {
      const result = await fn()
      return result
    } catch (error) {
      success = false
      throw error
    } finally {
      const duration = performance.now() - start
      const metric: PerformanceMetric = {
        operation,
        duration,
        success,
        metadata,
        timestamp: new Date(),
        correlationId: metadata?.correlationId as string | undefined
      }

      // Store metric with size limit to prevent memory leak
      const key = `${category}:${operation}`
      const metrics = recentMetrics.get(key) || []
      metrics.push(metric)

      // Keep only last 1000 metrics per operation
      if (metrics.length > 1000) {
        metrics.shift() // Remove oldest
      }

      recentMetrics.set(key, metrics)

      // Check thresholds
      const threshold = THRESHOLDS[category]
      if (duration > threshold.critical) {
        log.error('Critical performance threshold exceeded', {
          metadata: {
            operation,
            category,
            duration,
            threshold: threshold.critical,
            ...metadata
          }
        })

        void eventEmitter.emit('performance:critical', {
          operation,
          category,
          duration,
          threshold: threshold.critical,
          metadata
        })
      } else if (duration > threshold.warning) {
        log.warn('Performance warning threshold exceeded', {
          metadata: {
            operation,
            category,
            duration,
            threshold: threshold.warning,
            ...metadata
          }
        })
      }

      // Emit metric event
      void eventEmitter.emit('performance:metric', metric)
    }
  }

  trackStreamHealth(health: StreamHealthMetric) {
    const thresholds = THRESHOLDS.streamHealth
    const alerts: string[] = []

    // Check FPS
    if (health.fps < thresholds.fps.critical) {
      alerts.push(`Critical: FPS at ${health.fps.toString()} (threshold: ${thresholds.fps.critical.toString()})`)
    } else if (health.fps < thresholds.fps.warning) {
      alerts.push(`Warning: FPS at ${health.fps.toString()} (threshold: ${thresholds.fps.warning.toString()})`)
    }

    // Check dropped frames
    const droppedPercent = health.totalFrames > 0 ? (health.droppedFrames / health.totalFrames) * 100 : 0

    if (droppedPercent > thresholds.droppedFramesPercent.critical) {
      alerts.push(`Critical: Dropped frames at ${droppedPercent.toFixed(2)}%`)
    } else if (droppedPercent > thresholds.droppedFramesPercent.warning) {
      alerts.push(`Warning: Dropped frames at ${droppedPercent.toFixed(2)}%`)
    }

    // Check CPU usage
    if (health.cpuUsage > thresholds.cpuUsage.critical) {
      alerts.push(`Critical: CPU usage at ${health.cpuUsage.toString()}%`)
    } else if (health.cpuUsage > thresholds.cpuUsage.warning) {
      alerts.push(`Warning: CPU usage at ${health.cpuUsage.toString()}%`)
    }

    // Log and emit alerts
    if (alerts.length > 0) {
      log.warn('Stream health issues detected', {
        metadata: {
          alerts,
          health
        }
      })

      void eventEmitter.emit('streamHealth:alert', {
        alerts,
        health,
        timestamp: new Date()
      })
    }

    // Always emit the metric
    void eventEmitter.emit('streamHealth:metric', health)
  }

  getRecentMetrics(operation: string, category: string): PerformanceMetric[] {
    const key = `${category}:${operation}`
    return recentMetrics.get(key) || []
  }

  getAverageMetrics(
    operation: string,
    category: string
  ): {
    avgDuration: number
    successRate: number
    count: number
  } | null {
    const metrics = this.getRecentMetrics(operation, category)
    if (metrics.length === 0) return null

    const totalDuration = metrics.reduce((sum, m) => sum + m.duration, 0)
    const successCount = metrics.filter((m) => m.success).length

    return {
      avgDuration: totalDuration / metrics.length,
      successRate: (successCount / metrics.length) * 100,
      count: metrics.length
    }
  }

  shutdown() {
    clearInterval(this.cleanupInterval)
  }
}

// Export singleton instance
export const performanceMonitor = new PerformanceMonitor()

// Helper function for tracking WebSocket message performance
export async function trackWebSocketMessage<T>(
  messageType: string,
  fn: () => Promise<T>,
  metadata?: Record<string, unknown>
): Promise<T> {
  return performanceMonitor.trackOperation(messageType, 'websocket', fn, metadata)
}

// Helper function for tracking database operations
export async function trackDatabaseOperation<T>(
  operation: string,
  fn: () => Promise<T>,
  metadata?: Record<string, unknown>
): Promise<T> {
  return performanceMonitor.trackOperation(operation, 'database', fn, metadata)
}

// Helper function for tracking external API calls
export async function trackApiCall<T>(
  service: string,
  endpoint: string,
  fn: () => Promise<T>,
  metadata?: Record<string, unknown>
): Promise<T> {
  return performanceMonitor.trackOperation(`${service}:${endpoint}`, 'api', fn, metadata)
}
