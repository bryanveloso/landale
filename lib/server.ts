import { IncomingMessage, Server as NetServer, ServerResponse } from 'http'
import { NextApiResponse } from 'next'

import GameController from './game.controller'
import ObsController from './obs.controller'
import SocketController from './socket.controller'
import StreamController from './stream.controller'
import TwitchController from './twitch.controller'

export type CustomServer = NetServer & {
  game: GameController
  obs: ObsController
  socket: SocketController
  stream: StreamController
  twitch: TwitchController
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
