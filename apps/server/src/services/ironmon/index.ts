export * from './types'
export * from './handlers'

import { IronmonTCPServer } from './tcp-server'
import { createLogger } from '@landale/logger'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'ironmon' })

const tcpServer = new IronmonTCPServer()

export async function initialize() {
  try {
    await tcpServer.start()
    return tcpServer
  } catch (error) {
    log.error('Error initializing IronMON TCP Server', { error })
    throw error
  }
}

export async function shutdown() {
  await tcpServer.stop()
}
