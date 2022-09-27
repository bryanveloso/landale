import { IncomingMessage, Server as NetServer, ServerResponse } from 'http'
import { NextApiResponse } from 'next'

import ObsController from './obs.controller'
import TwitchController from './twitch.controller'
import SocketController from './socket.controller'
import StreamController from './stream.controller'

export type CustomServer = NetServer & {
  socket: SocketController
  obs: ObsController
  twitch: TwitchController
  stream: StreamController
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
