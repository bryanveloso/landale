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
import { BizhawkMessage } from './services/landale/kaizo';

export type SocketContext = {
  socket: Socket;
  isConnected: boolean;

  // Individual Message Pools
  messages: {
    bizhawk: BizhawkMessage[];
  };
};

export const socket = io('ws://saya.local:7177');

export const SocketContext = createContext<SocketContext>({
  socket,
  isConnected: false,
  messages: {
    bizhawk: [],
  },
});

export const SocketProvider: FC<PropsWithChildren> = ({ children }) => {
  const [isConnected, setIsConnected] = useState<boolean>(socket.connected);
  const [bizhawkMessages, setBizhawkMessages] = useState<BizhawkMessage[]>([]);

  const onConnect = useCallback(() => {
    console.log('🟢 useSocket() connected.');
    setIsConnected(true);
  }, []);

  const onDisconnect = useCallback(() => {
    console.log('🔴 useSocket() disconnected.');
    setIsConnected(false);
  }, []);

  const handleBizhawkMessage = useCallback((message: string) => {
    const data: BizhawkMessage = JSON.parse(message);
    setBizhawkMessages(previous => [...previous, data]);
  }, []);

  useEffect(() => {
    socket.on('connect', onConnect);
    socket.on('disconnect', onDisconnect);

    socket.on('bizhawk:message', handleBizhawkMessage);

    return () => {
      socket.off('connect', onConnect);
      socket.off('disconnect', onDisconnect);

      socket.off('bizhawk:message', handleBizhawkMessage);
    };
  }, [onConnect, onDisconnect, handleBizhawkMessage]);

  return (
    <SocketContext.Provider
      value={{ socket, isConnected, messages: { bizhawk: bizhawkMessages } }}
    >
      {children}
    </SocketContext.Provider>
  );
};

export const useSocket = () => {
  const { socket, isConnected, messages } = useContext(SocketContext);
  return { socket, isConnected, messages };
};
