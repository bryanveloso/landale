import { FC, PropsWithChildren, createContext, useEffect } from 'react';
import useWebSocket from 'react-use-websocket';

import { IronmonMessage } from './services/ironmon';
import { useQueryClient } from '@tanstack/react-query';

const socketUrl = 'ws://saya.local:7175';

const isHeartbeat = (data: string) => data === 'pong';

export type SocketContext = {
  isConnected: boolean;

  messages: {
    ironmon: IronmonMessage[];
  };
};

export const SocketContext = createContext<SocketContext>({
  isConnected: false,
  messages: {
    ironmon: [],
  },
});

export const SocketProvider: FC<PropsWithChildren> = ({ children }) => {
  const queryClient = useQueryClient();
  const { lastMessage, readyState } = useWebSocket(socketUrl, {
    filter: message => !isHeartbeat(message.data),
    heartbeat: true,
    onOpen: () => console.log('🟢 <SocketContext /> connected.'),
    onClose: () => console.log('🔴 <SocketContext /> disconnected.'),
    shouldReconnect: closeEvent => {
      console.log(closeEvent);
      return true;
    },
  });

  useEffect(() => {
    if (lastMessage && lastMessage.data) {
      console.log(JSON.parse(lastMessage.data));
    }
  }, [lastMessage, queryClient]);

  return (
    <SocketContext
      value={{
        isConnected: readyState === 1,
        messages: {
          ironmon: [],
        },
      }}
    >
      {children}
    </SocketContext>
  );
};
