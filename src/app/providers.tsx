'use client'

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryStreamedHydration } from '@tanstack/react-query-next-experimental';
import { FC, PropsWithChildren, useState } from 'react';

import { SocketProvider } from '@/lib/socket.provider';

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
      <QueryClientProvider client={queryClient}>
        <ReactQueryStreamedHydration>{children}</ReactQueryStreamedHydration>
      </QueryClientProvider>
    </SocketProvider>
  );
};
