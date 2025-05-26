import chalk from 'chalk'
import pino from 'pino'

// Import env separately to avoid circular dependency
const isDevelopment = process.env.NODE_ENV !== 'production'
const useStructuredLogging = process.env.STRUCTURED_LOGGING === 'true'
const logLevel = process.env.LOG_LEVEL || (isDevelopment ? 'debug' : 'info')

// Create the underlying pino logger for when we need structured output
const pinoLogger = pino({
  name: 'landale-server',
  level: logLevel,
  transport: useStructuredLogging && isDevelopment
    ? {
        target: 'pino-pretty',
        options: {
          colorize: true,
          translateTime: 'HH:MM:ss',
          ignore: 'pid,hostname'
        }
      }
    : undefined
})

// Pretty console logger that maintains your existing style
class PrettyLogger {
  private module: string

  constructor(module: string) {
    this.module = module
  }

  info(message: string, ...args: any[]) {
    if (useStructuredLogging) {
      pinoLogger.info({ module: this.module, ...args[0] }, message)
    } else {
      console.log(`  ${chalk.green('•')}  ${message}`)
    }
  }

  error(message: string, error?: Error | any, ...args: any[]) {
    if (useStructuredLogging) {
      pinoLogger.error({ module: this.module, error, ...args }, message)
    } else {
      console.error(`  ${chalk.red('•')}  ${message}`, error || '')
    }
  }

  warn(message: string, ...args: any[]) {
    if (useStructuredLogging) {
      pinoLogger.warn({ module: this.module, ...args[0] }, message)
    } else {
      console.warn(`  ${chalk.yellow('•')}  ${message}`)
    }
  }

  debug(message: string, ...args: any[]) {
    if (useStructuredLogging) {
      pinoLogger.debug({ module: this.module, ...args[0] }, message)
    } else if (isDevelopment) {
      console.log(`  ${chalk.gray('○')}  ${message}`)
    }
  }
}

// Export a logger that respects your style
export const logger = new PrettyLogger('main')

// Create child loggers for different modules
export const createLogger = (module: string) => {
  return new PrettyLogger(module)
}