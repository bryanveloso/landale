import { Server, ServerResponse } from 'http'
import { NextApiResponse } from 'next'

import ObsController from './obs.controller'
import SocketController from './socket.controller'
import TwitchConteroller from './twitch.controller'

// import ObsController from './obs'
// import SnapController from './snap'
// import GiveawaysController from './giveaways'
// import TwitchController from './twitch'
// import StreamController from './stream'

export type CustomServer = Server & {
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
