import { FC, PropsWithChildren, createContext, useEffect } from 'react';
import useWebSocket from 'react-use-websocket';

import { IronmonMessage } from './services/ironmon';
import { useQueryClient } from '@tanstack/react-query';

type SocketMessage = { source: 'tcp' } & IronmonMessage;

const socketUrl = 'ws://saya.local:7175';

const isHeartbeat = (data: string) => data === 'pong';

export const SocketContext = createContext<{
  isConnected: boolean;
}>({
  isConnected: false,
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
      const { source, type, metadata } = JSON.parse(
        lastMessage.data
      ) as SocketMessage;
      switch (source) {
        case 'tcp':
          console.log(source, type, metadata);
          queryClient.setQueryData(['ironmon', type], metadata);
          break;
        default:
          break;
      }
    }
  }, [lastMessage, queryClient]);

  return (
    <SocketContext
      value={{
        isConnected: readyState === 1,
      }}
    >
      {children}
    </SocketContext>
  );
};
