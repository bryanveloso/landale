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
        <div className="fixed bottom-4 right-4 bg-yellow-500 text-black px-2 py-1 rounded text-xs font-bold z-[10001]">
          DEV MODE
        </div>
      )}
    </RootDocument>
  )
}
