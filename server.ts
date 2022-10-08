import { createServer, IncomingMessage, request, RequestListener } from 'http'
import httpProxy from 'http-proxy'
import next from 'next'
import ngrok from 'ngrok'
import { loadEnvConfig } from '@next/env'
import { pinoHttp } from 'pino-http'
import { parse } from 'url'

import { CustomServer, CustomServerResponse } from './lib'
import SocketController from './lib/socket.controller'
import ObsController from './lib/obs.controller'
import TwitchController from './lib/twitch.controller'
import { logger } from './logger'
import StreamController from './lib/stream.controller'
import GameController from './lib/game.controller'

loadEnvConfig('./', process.env.NODE_ENV !== 'production', logger)

const dev = process.env.NODE_ENV !== 'production'
const hostname = 'localhost'
const port = 8008
const app = next({ dev, hostname, port })
const handle = app.getRequestHandler()
const url = `http://${hostname}:${port}`

let server: CustomServer

const requestLogger = pinoHttp({ logger, useLevel: 'debug' })

const listener = async (req: IncomingMessage, res: CustomServerResponse) => {
  try {
    res.server = server
    requestLogger(req, res)

    const parsedUrl = parse(req.url as string, true)
    await handle(req, res, parsedUrl)
  } catch (err) {
    logger.error(`Error occured handling`, req.url, err)
    res.statusCode = 500
    res.end('internal server error')
  }
}

const init = async () => {
  httpProxy
    .createProxyServer({ target: `${url}/api/twitch`, ignorePath: true })
    .listen(8009)

  await app.prepare()
  server = createServer(listener as RequestListener) as CustomServer
  server.listen(port, async () => {
    logger.info(`Ready on ${url}`)

    await ngrok.connect({
      addr: 8009,
      authtoken: process.env.NGROK_AUTH_TOKEN,
      hostname: process.env.NGROK_HOSTNAME,
      onLogEvent: logEventMessage => {
        logger.debug(logEventMessage)
      }
    })
  })

  const socketController = new SocketController(server)
  const obsController = new ObsController(socketController)
  const twitchController = new TwitchController(server, obsController)
  const streamController = new StreamController(twitchController)
  const gameController = new GameController(
    server,
    obsController,
    twitchController
  )

  server.socket = socketController
  server.obs = obsController
  server.twitch = twitchController
  server.stream = streamController
  server.game = gameController
}

init()
