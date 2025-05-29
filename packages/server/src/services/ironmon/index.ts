export * from './types'
export * from './handlers'

import { IronmonTCPServer } from './tcp-server'

const tcpServer = new IronmonTCPServer()

export async function initialize() {
  try {
    await tcpServer.start()
    return tcpServer
  } catch (error) {
    console.error('Error initializing IronMON TCP Server:', error)
    throw error
  }
}

export async function shutdown() {
  await tcpServer.stop()
}
