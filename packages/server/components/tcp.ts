import type { Server, TCPSocketListener, Socket } from 'bun';

const handleOpen = (socket: Socket<{}>) => {
  console.log(`🔀 TCP: Socket opened by ${socket.remoteAddress}`);
};

const handleData = (socket: Socket<{}>, data: Buffer, wss: Server) => {
  console.log(
    `🔀 TCP: Received data from ${socket.remoteAddress}: ${data.toString('utf-8')}`
  );

  const payload = {
    source: 'tcp',
    ...JSON.parse(data.toString().split(' ')[1]),
  };

  wss.publish('transport', JSON.stringify(payload));
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
