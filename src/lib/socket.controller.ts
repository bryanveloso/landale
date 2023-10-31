import { Server as ServerIO } from 'socket.io'

import { CustomServer } from './server'

export default class SocketController {
  socketServer: ServerIO

  constructor(server: CustomServer) {
    this.socketServer = new ServerIO(server)
  }

  emit(event: string, payload: unknown) {
    console.log(`Emitting: ${event} with payload ${JSON.stringify(payload)}`)
    return this.socketServer.emit(event, payload)
  }
}
