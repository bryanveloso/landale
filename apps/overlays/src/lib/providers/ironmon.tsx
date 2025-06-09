import { type FC, type PropsWithChildren, createContext, useContext, useState, useEffect } from 'react'
import { useIronmonSubscription } from '@/lib/hooks/use-ironmon'
import { useQueryClient } from '@tanstack/react-query'

interface IronmonContextValue {
  isConnected: boolean
  hasData: boolean
}

const IronmonContext = createContext<IronmonContextValue>({
  isConnected: false,
  hasData: false
})

export const useIronmon = () => {
  const context = useContext(IronmonContext)
  if (!context) {
    throw new Error('useIronmon must be used within IronmonProvider')
  }
  return context
}

export const IronmonProvider: FC<PropsWithChildren> = ({ children }) => {
  const [isConnected] = useState(true) // Assume connected initially
  const [hasData, setHasData] = useState(false)
  const queryClient = useQueryClient()

  // Initialize IronMON subscriptions
  useIronmonSubscription()

  // Monitor for data updates instead of WebSocket connection
  useEffect(() => {
    const checkData = () => {
      const checkpointData = queryClient.getQueryData(['ironmon', 'checkpoint'])
      const seedData = queryClient.getQueryData(['ironmon', 'seed'])
      const initData = queryClient.getQueryData(['ironmon', 'init'])

      setHasData(Boolean(checkpointData || seedData || initData))
    }

    // Check immediately
    checkData()

    // Subscribe to query cache updates
    const unsubscribe = queryClient.getQueryCache().subscribe(() => {
      checkData()
    })

    return () => {
      unsubscribe()
    }
  }, [queryClient])

  return <IronmonContext.Provider value={{ isConnected, hasData }}>{children}</IronmonContext.Provider>
}
