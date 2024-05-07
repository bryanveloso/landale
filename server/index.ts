import chalk from 'chalk';

import { version } from '~/package.json';

declare module 'bun' {
  interface Env {
    LANDALE_WEBSOCKET_PORT: number;
    LANDALE_TCPSOCKET_PORT: number;
  }
}

console.log(chalk.bold.green(`Landale Overlay System v${version}`));
console.log(`Starting Server: Using Bun version ${chalk.yellow(Bun.version)}`);

const ws = Bun.serve({
  hostname: '0.0.0.0',
  port: process.env.LANDALE_WEBSOCKET_PORT,
  fetch(req, server) {
    if (server.upgrade(req)) return;
    return new Response('Upgrade failed', { status: 500 });
  },
  websocket: {
    message(ws, message) {
      console.log(message);
    },
    open(ws) {
      console.log('WebSocket opened');
    },
    close(ws, code, message) {
      console.log('WebSocket closed', code, message);
    },
    drain(ws) {
      console.log('WebSocket drained');
    },
  },
});

console.log(`WebSocket server listening on ${ws.hostname}:${ws.port}`);

const tcp = Bun.listen<{}>({
  hostname: '0.0.0.0',
  port: process.env.LANDALE_TCPSOCKET_PORT,
  socket: {
    data(socket, data) {
      console.log(`Recieved data: ${data.toString('utf-8')}`);
    },
    open(socket) {
      console.log('Socket opened');
    },
    close(socket) {
      console.log('Socket closed');
    },
    drain(socket) {
      console.log('Socket drained');
    },
    error(socket, error) {
      console.log(error);
    },
  },
});

console.log(`TCPSocket server listening on ${tcp.hostname}:${tcp.port}`);
