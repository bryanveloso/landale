import React, { Suspense } from 'react';
import { QueryClient } from '@tanstack/react-query';
import { createRootRouteWithContext, Outlet } from '@tanstack/react-router';

export const Route = createRootRouteWithContext<{
  queryClient: QueryClient;
}>()({
  component: Root,
});

// Lazy load the devtools if running outside of OBS Studio.
const ReactQueryDevtools =
  'obsstudio' in window
    ? () => null
    : React.lazy(() =>
        import('@tanstack/react-query-devtools').then(res => ({
          default: res.ReactQueryDevtools,
        }))
      );
const TanStackRouterDevtools =
  'obsstudio' in window
    ? () => null
    : React.lazy(() =>
        import('@tanstack/router-devtools').then(res => ({
          default: res.TanStackRouterDevtools,
        }))
      );

function Root() {
  return (
    <>
      <Outlet />
      <Suspense>
        <ReactQueryDevtools />
        <TanStackRouterDevtools />
      </Suspense>
    </>
  );
}
