import { LogLevel, LogContext, Logger, serializeError } from './config'

export * from './config'

// Browser-safe configuration
interface BrowserLoggerConfig {
  service: string
  level?: LogLevel
  endpoint?: string // For remote logging
  bufferSize?: number // Buffer logs before sending
  flushInterval?: number // Auto-flush interval in ms
  enableConsole?: boolean
  sampleRate?: number
}

// Log buffer for batching
interface LogEntry {
  timestamp: string
  level: LogLevel
  service: string
  message: string
  context?: LogContext
  url: string
  userAgent: string
}

export class BrowserLogger implements Logger {
  private config: Required<BrowserLoggerConfig>
  private buffer: LogEntry[] = []
  private flushTimer?: number
  private levels: Record<LogLevel, number> = {
    fatal: 60,
    error: 50,
    warn: 40,
    info: 30,
    debug: 20,
    trace: 10,
    silent: 0
  }
  
  constructor(config: BrowserLoggerConfig) {
    this.config = {
      level: 'info',
      endpoint: undefined,
      bufferSize: 100,
      flushInterval: 5000,
      enableConsole: true,
      sampleRate: 1,
      ...config
    }
    
    // Set up auto-flush if endpoint is configured
    if (this.config.endpoint && this.config.flushInterval > 0) {
      this.flushTimer = window.setInterval(() => this.flush(), this.config.flushInterval)
    }
    
    // Flush on page unload
    if (this.config.endpoint) {
      window.addEventListener('beforeunload', () => this.flush())
      window.addEventListener('unload', () => this.flush())
    }
  }
  
  private shouldLog(level: LogLevel): boolean {
    if (Math.random() > this.config.sampleRate) return false
    return this.levels[level] >= this.levels[this.config.level]
  }
  
  private log(level: LogLevel, message: string, context?: LogContext): void {
    if (!this.shouldLog(level)) return
    
    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      service: this.config.service,
      message,
      context,
      url: window.location.href,
      userAgent: navigator.userAgent
    }
    
    // Console output
    if (this.config.enableConsole) {
      const consoleMethod = level === 'fatal' || level === 'error' ? 'error' :
                          level === 'warn' ? 'warn' :
                          level === 'debug' || level === 'trace' ? 'debug' :
                          'log'
      
      console[consoleMethod](`[${level.toUpperCase()}] ${message}`, context || '')
    }
    
    // Buffer for remote logging
    if (this.config.endpoint) {
      this.buffer.push(entry)
      
      // Flush if buffer is full
      if (this.buffer.length >= this.config.bufferSize) {
        this.flush()
      }
    }
  }
  
  private async flush(): Promise<void> {
    if (!this.config.endpoint || this.buffer.length === 0) return
    
    const logs = [...this.buffer]
    this.buffer = []
    
    try {
      // Use sendBeacon for reliability on page unload
      if (navigator.sendBeacon) {
        const blob = new Blob([JSON.stringify({ logs })], { type: 'application/json' })
        navigator.sendBeacon(this.config.endpoint, blob)
      } else {
        // Fallback to fetch
        await fetch(this.config.endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ logs }),
          keepalive: true
        })
      }
    } catch (error) {
      // Put logs back in buffer on failure
      this.buffer.unshift(...logs)
      console.error('Failed to send logs:', error)
    }
  }
  
  // Logger interface implementation
  fatal(message: string, context?: LogContext): void {
    this.log('fatal', message, context)
  }
  
  error(message: string, context?: LogContext): void {
    this.log('error', message, context)
  }
  
  warn(message: string, context?: LogContext): void {
    this.log('warn', message, context)
  }
  
  info(message: string, context?: LogContext): void {
    this.log('info', message, context)
  }
  
  debug(message: string, context?: LogContext): void {
    this.log('debug', message, context)
  }
  
  trace(message: string, context?: LogContext): void {
    this.log('trace', message, context)
  }
  
  child(options: Record<string, unknown>): Logger {
    // Create a new logger with merged context
    const childLogger = new BrowserLogger(this.config)
    // Add parent context to all child logs
    const originalLog = childLogger.log.bind(childLogger)
    childLogger.log = (level, message, context) => {
      originalLog(level, message, {
        ...context,
        metadata: {
          ...options,
          ...context?.metadata
        }
      })
    }
    return childLogger
  }
  
  time(label: string): () => void {
    const start = performance.now()
    return () => {
      const duration = performance.now() - start
      this.debug(`Timer ${label}`, { operation: label, duration })
    }
  }
  
  measure<T>(label: string, fn: () => T): T {
    const start = performance.now()
    try {
      const result = fn()
      const duration = performance.now() - start
      this.debug(`Operation completed: ${label}`, { 
        operation: label, 
        duration, 
        status: 'success' 
      })
      return result
    } catch (error) {
      const duration = performance.now() - start
      this.error(`Operation failed: ${label}`, {
        operation: label,
        duration,
        status: 'failure',
        error: serializeError(error)
      })
      throw error
    }
  }
  
  async measureAsync<T>(label: string, fn: () => Promise<T>): Promise<T> {
    const start = performance.now()
    try {
      const result = await fn()
      const duration = performance.now() - start
      this.debug(`Operation completed: ${label}`, { 
        operation: label, 
        duration, 
        status: 'success' 
      })
      return result
    } catch (error) {
      const duration = performance.now() - start
      this.error(`Operation failed: ${label}`, {
        operation: label,
        duration,
        status: 'failure',
        error: serializeError(error)
      })
      throw error
    }
  }
  
  // Clean up method
  destroy(): void {
    if (this.flushTimer) {
      window.clearInterval(this.flushTimer)
    }
    this.flush()
  }
}

// Factory function for consistency with server logger
export function createLogger(config: BrowserLoggerConfig): Logger {
  return new BrowserLogger(config)
}

// Performance monitoring helper
export function trackPerformance(logger: Logger): void {
  // Track page load performance
  if (window.performance && window.performance.timing) {
    window.addEventListener('load', () => {
      const timing = window.performance.timing
      const loadTime = timing.loadEventEnd - timing.navigationStart
      const domReady = timing.domContentLoadedEventEnd - timing.navigationStart
      const firstPaint = performance.getEntriesByType('paint')[0]?.startTime || 0
      
      logger.info('Page performance metrics', {
        performance: {
          duration: loadTime,
          memory: (performance as any).memory
        },
        metadata: {
          domReady,
          firstPaint,
          resources: performance.getEntriesByType('resource').length
        }
      })
    })
  }
  
  // Track JavaScript errors
  window.addEventListener('error', (event) => {
    logger.error('Uncaught error', {
      error: {
        message: event.message,
        stack: event.error?.stack,
        type: event.error?.constructor.name || 'Error',
        code: undefined
      },
      metadata: {
        filename: event.filename,
        lineno: event.lineno,
        colno: event.colno
      }
    })
  })
  
  // Track unhandled promise rejections
  window.addEventListener('unhandledrejection', (event) => {
    logger.error('Unhandled promise rejection', {
      error: serializeError(event.reason)
    })
  })
}