import {
  type FC,
  type PropsWithChildren,
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
} from 'react';
import { io, type Socket } from 'socket.io-client';

export type SocketContext = {
  socket: Socket;
  isConnected: boolean;
};

export const socket = io('ws://saya.local:7177');

export const SocketContext = createContext<SocketContext>({
  socket,
  isConnected: false,
});

export const SocketProvider: FC<PropsWithChildren> = ({ children }) => {
  const [isConnected, setIsConnected] = useState<boolean>(socket.connected);

  const onConnect = useCallback(() => {
    console.log('🟢 useSocket() connected.');
    setIsConnected(true);
  }, []);

  const onDisconnect = useCallback(() => {
    console.log('🔴 useSocket() disconnected.');
    setIsConnected(false);
  }, []);

  useEffect(() => {
    socket.on('connect', onConnect);
    socket.on('disconnect', onDisconnect);

    return () => {
      socket.off('connect', onConnect);
      socket.off('disconnect', onDisconnect);
    };
  }, [socket]);

  return (
    <SocketContext.Provider value={{ socket, isConnected }}>
      {children}
    </SocketContext.Provider>
  );
};

export const useSocket = () => {
  const { socket, isConnected } = useContext(SocketContext);
  return { socket, isConnected };
};
