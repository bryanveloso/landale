import { useEffect, useState } from 'react';
import { Socket, io } from 'socket.io-client';

let initialized = false;
let socket: Socket | null = null;

export const useSocket = () => {
  const [isConnected, setIsConnected] = useState<boolean>(false);

  const init = async () => {
    initialized = true;
    socket = io('ws://127.0.0.1:7177');

    socket.on('connect', () => {
      console.log('🟢 useSocket() connected.');
      setIsConnected(true);
    });
    socket.on('disconnect', () => {
      console.log('🔴 useSocket() disconnected.');
      setIsConnected(false);
    });

    socket.connect();
  };

  useEffect(() => {
    if (!initialized) init();

    return () => {
      socket?.close();
      initialized = false;
      socket = null;
    };
  }, []);

  return { socket, isConnected };
};
