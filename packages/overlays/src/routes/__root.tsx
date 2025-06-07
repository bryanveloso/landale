import React, { type FC, type PropsWithChildren, Suspense } from 'react'
import { QueryClient } from '@tanstack/react-query'
import { createRootRouteWithContext, Outlet } from '@tanstack/react-router'

import { DefaultCatchBoundary } from '@/components/error'

export const Route = createRootRouteWithContext<{
  queryClient: QueryClient
}>()({
  component: RootComponent,
  errorComponent: ({ error }) => (
    <RootDocument>
      <DefaultCatchBoundary error={error} reset={undefined as never} />
    </RootDocument>
  )
})

// Lazy load the devtools if running outside of OBS Studio.
const ReactQueryDevtools =
  'obsstudio' in window
    ? () => null
    : React.lazy(() =>
        import('@tanstack/react-query-devtools').then((res) => ({
          default: res.ReactQueryDevtools
        }))
      )
const TanStackRouterDevtools =
  'obsstudio' in window
    ? () => null
    : React.lazy(() =>
        import('@tanstack/react-router-devtools').then((res) => ({
          default: res.TanStackRouterDevtools
        }))
      )

const RootDocument: FC<PropsWithChildren> = ({ children }) => {
  return (
    <>
      {children}
      {/* <Suspense>
        <ReactQueryDevtools />
        <TanStackRouterDevtools />
      </Suspense> */}
    </>
  )
}

function RootComponent() {
  return (
    <RootDocument>
      <Outlet />
    </RootDocument>
  )
}
