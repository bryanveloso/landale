import { Server, ServerResponse } from 'http'
import { NextApiResponse } from 'next'

import CategoryController from './category.controller'
import ObsController from './obs.controller'
import SocketController from './socket.controller'
import TwitchConteroller from './twitch.controller'

export type CustomServer = Server & {
  category: CategoryController
  obs: ObsController
  socket: SocketController
  twitch: TwitchConteroller
}

export type CustomServerResponse = ServerResponse & {
  server: CustomServer
}

export type CustomNextApiResponse = NextApiResponse & {
  server: CustomServer
}
