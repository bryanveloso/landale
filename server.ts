import { createServer, IncomingMessage, RequestListener } from 'http'
import next from 'next'
import { loadEnvConfig } from '@next/env'
import { parse } from 'url'

import { CustomServer, CustomServerResponse } from './lib'
import SocketController from './lib/socket.controller'
import ObsController from './lib/obs.controller'

loadEnvConfig('./', process.env.NODE_ENV !== 'production')

const dev = process.env.NODE_ENV !== 'production'
const hostname = 'localhost'
const port = 8008
const app = next({ dev, hostname, port })
const handle = app.getRequestHandler()
const url = `http://${hostname}:${port}`

let server: CustomServer

const listener = async (req: IncomingMessage, res: CustomServerResponse) => {
  try {
    res.server = server

    const parsedUrl = parse(req.url as string, true)
    await handle(req, res, parsedUrl)
  } catch (err) {
    console.error(`Error occured handling`, req.url, err)
    res.statusCode = 500
    res.end('internal server error')
  }
}

const init = async () => {
  await app.prepare()
  server = createServer(listener as RequestListener) as CustomServer
  server.listen(port, () => console.log(`Ready on ${url}`))

  const socketController = new SocketController(server)
  const obsController = new ObsController(socketController)

  server.socket = socketController
  server.obs = obsController
}

init()
