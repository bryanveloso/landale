import '@fontsource-variable/inter'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'

import { OBSProvider } from '@/lib/providers/obs'
import { QueryProvider, queryClient } from '@/lib/providers/query'

import { routeTree } from './routeTree.gen'

import './index.css'

const router = createRouter({
  routeTree,
  context: { queryClient },
  defaultPreload: 'intent',
  defaultPreloadStaleTime: 0
})

// Register router for type-safety.
declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryProvider>
      <OBSProvider>
        <RouterProvider router={router} />
      </OBSProvider>
    </QueryProvider>
  </React.StrictMode>
)
