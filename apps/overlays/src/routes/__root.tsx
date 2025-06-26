import { type FC, type PropsWithChildren } from 'react'
import { type QueryClient } from '@tanstack/react-query'
import { createRootRouteWithContext, Outlet } from '@tanstack/react-router'
import { useOBS } from '@/lib/obs-detection'

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
  const obsInfo = useOBS()

  return (
    <RootDocument>
      <Outlet />

      {/* Development indicator - only shows in browser */}
      {!obsInfo.isOBS && (
        <div className="fixed right-4 bottom-4 z-[10001] rounded bg-yellow-500 px-2 py-1 text-xs font-bold text-black">
          DEV MODE
        </div>
      )}
    </RootDocument>
  )
}
