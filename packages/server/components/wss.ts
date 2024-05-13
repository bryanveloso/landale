import type { Server, ServerWebSocket } from 'bun';

const handleOpen = (ws: ServerWebSocket<{}>) => {
  console.log(`📶 WSS: Socket opened by ${ws.remoteAddress}`);
  ws.subscribe('transport');
};

const handleMessage = (
  ws: ServerWebSocket<{}>,
  server: Server,
  message: string | Buffer
) => {
  if (message === 'ping') {
    ws.send('pong');
  } else {
    console.log(`📶 WSS: Received message: ${message}`);
    server.publish('transport', message);
  }
};

const handleClose = (
  ws: ServerWebSocket<{}>,
  code: number,
  message: string
) => {
  console.log(
    `📶 WSS: Socket closed by ${ws.remoteAddress} with code ${code}: ${message}`
  );
};

const init = async (): Promise<Server> => {
  const server: Server = Bun.serve<{}>({
    hostname: '0.0.0.0',
    port: 7175,

    fetch(req, server) {
      if (server.upgrade(req)) return;
      return new Response('Upgrade failed', { status: 500 });
    },

    websocket: {
      open: ws => handleOpen(ws),
      message: (ws, message) => handleMessage(ws, server, message),
      close: (ws, code, message) => handleClose(ws, code, message),
    },
  });

  return server;
};

export const WebSocketServer = { init };
