import type { Server, TCPSocketListener, Socket } from 'bun';

import * as ironmon from './ironmon';

const handleOpen = (socket: Socket<{}>) => {
  console.log(`🔀 TCP: Socket opened by ${socket.remoteAddress}`);
};

const handleData = async (socket: Socket<{}>, data: Buffer, wss: Server) => {
  // Handle the incoming message and handle multiple payloads appearing in the same message.
  let buffer = '';
  buffer += data.toString('utf-8');

  while (buffer.length > 0) {
    const space = buffer.indexOf(' ');
    if (space === -1) {
      break;
    }

    const length = parseInt(buffer.slice(0, space), 10);
    if (isNaN(length)) {
      console.error(
        `🔀 TCP: Invalid message length: ${buffer.slice(0, space)}`
      );
      buffer = '';
      break;
    }

    const startIndex = space + 1;
    const endIndex = startIndex + length;

    if (buffer.length >= endIndex) {
      const message = buffer.slice(startIndex, endIndex);
      console.log(
        `🔀 TCP: Received data from ${socket.remoteAddress}: ${message}`
      );

      // Attempt to process the message.
      try {
        const parsedMessage = JSON.parse(message);
        const payload = await ironmon.handleMessage(parsedMessage);
        console.log(`🔀 TCP: Processed payload: ${JSON.stringify(payload)}`);
        wss.publish('transport', JSON.stringify(payload));
      } catch (e: any) {
        console.error(`🔀 TCP: Error processing message: ${e}`);
      }

      buffer = buffer.slice(endIndex);
    } else {
      break;
    }
  }
};

const handleClose = (socket: Socket<{}>) => {
  console.log(`🔀 TCP: Socket closed by ${socket.remoteAddress}`);
};

const handleError = (socket: Socket<{}>, error: Error) => {
  console.error(
    `🔀 TCP: Socket error from ${socket.remoteAddress}: ${error.message}`
  );
};

const init = async (wss: Server): Promise<TCPSocketListener> => {
  const server = Bun.listen<{}>({
    hostname: '0.0.0.0',
    port: 8080,
    socket: {
      open: socket => handleOpen(socket),
      data: (socket, data) => handleData(socket, data, wss),
      close: socket => handleClose(socket),
      error: (socket, error) => handleError(socket, error),
    },
  });

  return server;
};

export const TCPSocketServer = { init };
