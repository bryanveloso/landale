import '@fontsource-variable/inter';
import React from 'react';
import ReactDOM from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RouterProvider, createRouter } from '@tanstack/react-router';

import { routeTree } from './routeTree.gen';

import './index.css';
import { SocketProvider } from './lib/socket.provider';
import { OBSProvider } from './lib/obs.provider';

const queryClient = new QueryClient();

const router = createRouter({
  routeTree,
  context: { queryClient },
  defaultPreload: 'intent',
  defaultPreloadStaleTime: 0,
});

// Register router for type-safety.
declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router;
  }
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <SocketProvider>
        <OBSProvider>
          <RouterProvider router={router} />
        </OBSProvider>
      </SocketProvider>
    </QueryClientProvider>
  </React.StrictMode>
);
