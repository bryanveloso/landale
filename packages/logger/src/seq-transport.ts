import build from 'pino-abstract-transport'

interface SeqTransportOptions {
  serverUrl: string
  apiKey?: string
  batchSize?: number
  flushInterval?: number
}

interface SeqEvent {
  '@t': string
  '@l': string
  '@mt': string
  '@x'?: string
  [key: string]: unknown
}

const levelMap: Record<number, string> = {
  10: 'Verbose',  // trace
  20: 'Debug',    // debug
  30: 'Information', // info
  40: 'Warning',  // warn
  50: 'Error',    // error
  60: 'Fatal'     // fatal
}

interface PinoLogObject {
  time: number
  level: number
  msg: string
  err?: { stack?: string }
  [key: string]: unknown
}

export default function (options: SeqTransportOptions) {
  const { serverUrl, apiKey, batchSize = 100, flushInterval = 1000 } = options

  let batch: SeqEvent[] = []
  let timer: NodeJS.Timeout | null = null

  const flush = async () => {
    if (batch.length === 0) return

    const events = batch.map(e => JSON.stringify(e)).join('\n')
    batch = []

    try {
      const headers: Record<string, string> = {
        'Content-Type': 'application/vnd.serilog.clef'
      }

      if (apiKey) {
        headers['X-Seq-ApiKey'] = apiKey
      }

      await fetch(`${serverUrl}/api/events/raw`, {
        method: 'POST',
        headers,
        body: events
      })
    } catch (error) {
      console.error('Failed to send logs to Seq:', error)
    }
  }

  return build(async function (source: AsyncIterable<PinoLogObject>) {
    for await (const obj of source) {
      const seqEvent: SeqEvent = {
        '@t': new Date(obj.time).toISOString(),
        '@l': levelMap[obj.level] || 'Information',
        '@mt': obj.msg,
        ...obj
      }

      // Handle error objects
      if (obj.err?.stack) {
        seqEvent['@x'] = obj.err.stack
      }

      // Remove pino internals
      delete seqEvent.time
      delete seqEvent.level
      delete seqEvent.msg
      delete seqEvent.err
      delete seqEvent.pid
      delete seqEvent.hostname

      batch.push(seqEvent)

      if (batch.length >= batchSize) {
        await flush()
      } else if (!timer) {
        timer = setTimeout(() => {
          void flush()
          timer = null
        }, flushInterval)
      }
    }
  }, {
    async close() {
      if (timer) {
        clearTimeout(timer)
        timer = null
      }
      await flush()
    }
  })
}
