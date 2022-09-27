import { Server as ServerIO } from 'socket.io'

import { logger } from 'logger'

import { CustomServer } from './server'

export default class SocketController {
  socketServer: ServerIO

  constructor(server: CustomServer) {
    this.socketServer = new ServerIO(server)
  }

  emit(event: string, payload: unknown) {
    logger.info({ payload }, `Emitting "${event}"`)
    return this.socketServer.emit(event, payload)
  }
}
