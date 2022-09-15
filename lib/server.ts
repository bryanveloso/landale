import { IncomingMessage, Server as NetServer, ServerResponse } from 'http'
import { NextApiResponse } from 'next'

import SocketController from './socket.controller'
import ObsController from './obs.controller'

export type CustomServer = NetServer & {
  socket: SocketController
  obs: ObsController
}

export type CustomServerResponse = ServerResponse & {
  server?: CustomServer
}

export type CustomRequestListener = (
  req: IncomingMessage,
  res: CustomServerResponse
) => void

export type NextApiResponseServerIO = NextApiResponse & {
  server: CustomServer
}
