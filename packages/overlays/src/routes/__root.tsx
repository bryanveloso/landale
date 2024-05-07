import { QueryClient } from '@tanstack/react-query';
import { createRootRouteWithContext, Outlet } from '@tanstack/react-router';
import { TanStackRouterDevtools } from '@tanstack/router-devtools';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';

export const Route = createRootRouteWithContext<{
  queryClient: QueryClient;
}>()({
  component: Root,
});

function Root() {
  return (
    <>
      <hr />
      <Outlet />
      <ReactQueryDevtools />
      <TanStackRouterDevtools />
    </>
  );
}
