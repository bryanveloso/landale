import { createLogger } from '@landale/logger'
import { eventEmitter } from '@/events'
import prisma from '@landale/database'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'audit' })

export interface AuditEvent {
  id?: string
  timestamp: Date
  correlationId?: string
  action: AuditAction
  category: AuditCategory
  actor?: {
    type: 'system' | 'api' | 'websocket' | 'internal'
    id?: string
    ip?: string
  }
  resource?: {
    type: string
    id?: string
    name?: string
  }
  changes?: {
    before?: unknown
    after?: unknown
  }
  result: 'success' | 'failure'
  error?: string
  metadata?: Record<string, unknown>
}

export enum AuditCategory {
  // Stream operations
  STREAM = 'stream',
  // Configuration changes
  CONFIG = 'config',
  // Scene management
  SCENE = 'scene',
  // Connection events
  CONNECTION = 'connection',
  // Recording operations
  RECORDING = 'recording',
  // Service lifecycle
  SERVICE = 'service',
  // Security events
  SECURITY = 'security',
  // Performance events
  PERFORMANCE = 'performance'
}

export enum AuditAction {
  // Stream actions
  STREAM_START = 'stream.start',
  STREAM_STOP = 'stream.stop',
  STREAM_HEALTH_CRITICAL = 'stream.health.critical',

  // Config actions
  CONFIG_UPDATE = 'config.update',
  CONFIG_RESET = 'config.reset',

  // Scene actions
  SCENE_CHANGE = 'scene.change',
  SCENE_CREATE = 'scene.create',
  SCENE_DELETE = 'scene.delete',

  // Connection actions
  CONNECTION_ESTABLISHED = 'connection.established',
  CONNECTION_LOST = 'connection.lost',
  CONNECTION_FAILED = 'connection.failed',

  // Recording actions
  RECORDING_START = 'recording.start',
  RECORDING_STOP = 'recording.stop',
  RECORDING_PAUSE = 'recording.pause',
  RECORDING_RESUME = 'recording.resume',

  // Service actions
  SERVICE_START = 'service.start',
  SERVICE_STOP = 'service.stop',
  SERVICE_RESTART = 'service.restart',
  SERVICE_ERROR = 'service.error',

  // Security actions
  AUTH_SUCCESS = 'auth.success',
  AUTH_FAILURE = 'auth.failure',
  RATE_LIMIT_EXCEEDED = 'rate_limit.exceeded',

  // Performance actions
  PERFORMANCE_DEGRADED = 'performance.degraded',
  PERFORMANCE_CRITICAL = 'performance.critical'
}

class AuditLogger {
  private buffer: AuditEvent[] = []
  private flushInterval: NodeJS.Timeout
  private readonly FLUSH_INTERVAL = 5000 // 5 seconds
  private readonly BUFFER_SIZE = 100
  private isFlushing = false

  constructor() {
    // Periodically flush audit events to database
    this.flushInterval = setInterval(() => {
      void this.flush()
    }, this.FLUSH_INTERVAL)
  }

  async log(event: Omit<AuditEvent, 'id' | 'timestamp'>): Promise<void> {
    const auditEvent: AuditEvent = {
      ...event,
      timestamp: new Date()
    }

    // Add to buffer
    this.buffer.push(auditEvent)

    // Log based on severity
    if (event.result === 'failure' || event.category === AuditCategory.SECURITY) {
      log.warn('Audit event', { metadata: { audit: auditEvent } })
    } else {
      log.info('Audit event', { metadata: { audit: auditEvent } })
    }

    // Emit for real-time monitoring
    void eventEmitter.emit('audit:event', auditEvent)

    // Flush if buffer is full
    if (this.buffer.length >= this.BUFFER_SIZE) {
      void this.flush()
    }
  }

  private async flush(): Promise<void> {
    if (this.buffer.length === 0 || this.isFlushing) return

    this.isFlushing = true
    const events = [...this.buffer]
    this.buffer = []

    try {
      // Store in database
      await prisma.auditLog.createMany({
        data: events.map((event) => ({
          timestamp: event.timestamp,
          correlationId: event.correlationId,
          action: event.action,
          category: event.category,
          actorType: event.actor?.type,
          actorId: event.actor?.id,
          actorIp: event.actor?.ip,
          resourceType: event.resource?.type,
          resourceId: event.resource?.id,
          resourceName: event.resource?.name,
          changesBefore: event.changes?.before ? JSON.stringify(event.changes.before) : null,
          changesAfter: event.changes?.after ? JSON.stringify(event.changes.after) : null,
          result: event.result,
          error: event.error,
          metadata: event.metadata ? JSON.stringify(event.metadata) : null
        }))
      })

      log.debug('Flushed audit events to database', { metadata: { count: events.length } })
    } catch (error) {
      log.error('Failed to flush audit events', { error: error as Error, metadata: { eventCount: events.length } })

      // Re-add events to buffer for retry
      this.buffer.unshift(...events)
    } finally {
      this.isFlushing = false
    }
  }

  // Helper methods for common audit scenarios
  async logStreamStart(correlationId?: string, metadata?: Record<string, unknown>): Promise<void> {
    await this.log({
      action: AuditAction.STREAM_START,
      category: AuditCategory.STREAM,
      correlationId,
      result: 'success',
      metadata
    })
  }

  async logStreamStop(correlationId?: string, metadata?: Record<string, unknown>): Promise<void> {
    await this.log({
      action: AuditAction.STREAM_STOP,
      category: AuditCategory.STREAM,
      correlationId,
      result: 'success',
      metadata
    })
  }

  async logConfigChange(
    resource: string,
    before: unknown,
    after: unknown,
    correlationId?: string,
    actor?: AuditEvent['actor']
  ): Promise<void> {
    await this.log({
      action: AuditAction.CONFIG_UPDATE,
      category: AuditCategory.CONFIG,
      correlationId,
      actor,
      resource: {
        type: 'config',
        name: resource
      },
      changes: { before, after },
      result: 'success'
    })
  }

  async logSceneChange(fromScene: string | null, toScene: string, correlationId?: string): Promise<void> {
    await this.log({
      action: AuditAction.SCENE_CHANGE,
      category: AuditCategory.SCENE,
      correlationId,
      resource: {
        type: 'scene',
        name: toScene
      },
      changes: {
        before: fromScene,
        after: toScene
      },
      result: 'success'
    })
  }

  async logConnectionEvent(
    service: string,
    action: AuditAction,
    metadata?: Record<string, unknown>,
    error?: string
  ): Promise<void> {
    await this.log({
      action,
      category: AuditCategory.CONNECTION,
      resource: {
        type: 'service',
        name: service
      },
      result: error ? 'failure' : 'success',
      error,
      metadata
    })
  }

  async logSecurityEvent(
    action: AuditAction,
    actor: AuditEvent['actor'],
    metadata?: Record<string, unknown>,
    error?: string
  ): Promise<void> {
    await this.log({
      action,
      category: AuditCategory.SECURITY,
      actor,
      result: error ? 'failure' : 'success',
      error,
      metadata
    })
  }

  async logPerformanceEvent(action: AuditAction, metadata: Record<string, unknown>): Promise<void> {
    await this.log({
      action,
      category: AuditCategory.PERFORMANCE,
      result: 'failure', // Performance events are only logged when there's an issue
      metadata
    })
  }

  // Query methods
  async getRecentEvents(limit = 100): Promise<AuditEvent[]> {
    const events = await prisma.auditLog.findMany({
      take: limit,
      orderBy: { timestamp: 'desc' }
    })

    return events.map((event) => ({
      id: event.id,
      timestamp: event.timestamp,
      correlationId: event.correlationId || undefined,
      action: event.action as AuditAction,
      category: event.category as AuditCategory,
      actor: event.actorType
        ? {
            type: event.actorType as 'system' | 'api' | 'websocket' | 'internal',
            id: event.actorId || undefined,
            ip: event.actorIp || undefined
          }
        : undefined,
      resource: event.resourceType
        ? {
            type: event.resourceType,
            id: event.resourceId || undefined,
            name: event.resourceName || undefined
          }
        : undefined,
      changes: {
        before: event.changesBefore ? (JSON.parse(event.changesBefore) as unknown) : undefined,
        after: event.changesAfter ? (JSON.parse(event.changesAfter) as unknown) : undefined
      },
      result: event.result as 'success' | 'failure',
      error: event.error || undefined,
      metadata: event.metadata ? (JSON.parse(event.metadata) as Record<string, unknown>) : undefined
    }))
  }

  async shutdown(): Promise<void> {
    // Clear the interval
    clearInterval(this.flushInterval)

    // Flush remaining events
    await this.flush()
  }
}

// Export singleton instance
export const auditLogger = new AuditLogger()
