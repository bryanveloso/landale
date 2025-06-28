import { createLogger as createBaseLogger, createLoggerWithSeq as createSeqLogger } from '@landale/logger'
import { getSeqUrl } from '@landale/service-config'
import { env } from './env'

// Create logger with Seq if configured
export function createLogger(config: Parameters<typeof createBaseLogger>[0]) {
  if (env.SEQ_HOST) {
    const seqUrl = getSeqUrl()
    return createSeqLogger(config, seqUrl, env.SEQ_API_KEY)
  }
  
  return createBaseLogger(config)
}

// Re-export everything else
export * from '@landale/logger'