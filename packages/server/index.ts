import chalk from 'chalk';

import { version } from './package.json';

console.log(
  chalk.bold.green(`\n  LANDALE OVERLAY SYSTEM SERVER v${version}\n`)
);

const ws = Bun.serve({
  hostname: '0.0.0.0',
  port: 7175,
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

console.log(
  `  ${chalk.green('➜')}  ${chalk.bold('WebSocket Server')}: ${ws.hostname}:${ws.port}`
);

const tcp = Bun.listen<{}>({
  hostname: '0.0.0.0',
  port: 8080,
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

console.log(
  `  ${chalk.green('➜')}  ${chalk.bold('TCPSocket Server')}: ${tcp.hostname}:${tcp.port}`
);
