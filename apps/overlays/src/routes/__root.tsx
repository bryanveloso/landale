import { type FC, type PropsWithChildren } from 'react'
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

const RootDocument: FC<PropsWithChildren> = ({ children }) => {
  return <>{children}</>
}

function RootComponent() {
  return (
    <RootDocument>
      <Outlet />
    </RootDocument>
  )
}
