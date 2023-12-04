'use client'

import { SocketProvider } from '@/lib/socket.provider';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { FC, PropsWithChildren, useState } from 'react';

export const Providers: FC<PropsWithChildren> = ({ children }) => {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { staleTime: 60 * 1000 },
        },
      })
  );

  return (
    <SocketProvider>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </SocketProvider>
  );
};
