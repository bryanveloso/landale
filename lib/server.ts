import { IncomingMessage, Server as NetServer, ServerResponse } from 'http'
import { NextApiResponse } from 'next'

export type CustomServer = NetServer & {}

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
