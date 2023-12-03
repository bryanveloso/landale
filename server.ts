import chalk from 'chalk'
import { createServer, IncomingMessage, RequestListener } from 'http'
import httpProxy from 'http-proxy'
import next from 'next'
import { loadEnvConfig } from '@next/env'
import { parse } from 'url'

import { CustomServer, CustomServerResponse } from '@/lib'

import TwitchController from './src/lib/twitch.controller';
import CategoryController from './src/lib/category.controller';

loadEnvConfig('./', process.env.NODE_ENV !== 'production');

const dev = process.env.NODE_ENV !== 'production';
const hostname = 'localhost';
const port = 8088;
const app = next({ dev, hostname, port });
const handle = app.getRequestHandler();
const url = `http://${hostname}:${port}`;

let server: CustomServer;

const listener = async (req: IncomingMessage, res: CustomServerResponse) => {
  try {
    res.server = server;

    const parsedUrl = parse(req.url as string, true);
    const { pathname } = parsedUrl;

    await handle(req, res, parsedUrl);
  } catch (err) {
    console.error('Error occured handling request: ', req.url, err);
    res.statusCode = 500;
    res.end('Internal Server Error');
  }
};

const init = async () => {
  httpProxy
    .createProxyServer({ target: `${url}/api/twitch`, ignorePath: true })
    .listen(8089);

  await app.prepare();
  server = createServer(listener as unknown as RequestListener) as CustomServer;
  server.listen(port, () => {
    console.log(` ${chalk.green('✓')} Ready on ${url}`);
  });

  const categoryController = new CategoryController(server);
  const twitchController = new TwitchController(server);

  server.category = categoryController;
  server.twitch = twitchController;
};

init()
