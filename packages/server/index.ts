import chalk from 'chalk';

import { TCPSocketServer } from './components/tcp';
import { WebSocketServer } from './components/wss';

import { version } from './package.json';

console.log(
  chalk.bold.green(`\n  LANDALE OVERLAY SYSTEM SERVER v${version}\n`)
);

(async () => {
  const wss = await WebSocketServer.init();
  console.log(
    `  ${chalk.green('➜')}  ${chalk.bold('WebSocket Server')}: ${wss.hostname}:${wss.port}`
  );

  const tcp = await TCPSocketServer.init(wss);
  console.log(
    `  ${chalk.green('➜')}  ${chalk.bold('TCPSocket Server')}: ${tcp.hostname}:${tcp.port}\n`
  );
})();
