import { FC, PropsWithChildren, createContext, useContext, useState, useEffect } from 'react'
import { useIronmonSubscription } from '@/lib/hooks/use-ironmon'
import { useTRPCClient } from '@/lib/trpc'

interface IronmonContextValue {
  isConnected: boolean
}

const IronmonContext = createContext<IronmonContextValue>({
  isConnected: false
})

export const useIronmon = () => {
  const context = useContext(IronmonContext)
  if (!context) {
    throw new Error('useIronmon must be used within IronmonProvider')
  }
  return context
}

export const IronmonProvider: FC<PropsWithChildren> = ({ children }) => {
  const [isConnected, setIsConnected] = useState(false)
  const trpcClient = useTRPCClient()

  // Initialize IronMON subscriptions
  useIronmonSubscription()

  // Monitor WebSocket connection status
  useEffect(() => {
    const checkConnection = () => {
      // Check if the WebSocket is connected by checking the client state
      const wsTransport = (trpcClient as any).links?.[1]?.client
      if (wsTransport?.getConnection?.()?.readyState === WebSocket.OPEN) {
        setIsConnected(true)
      } else {
        setIsConnected(false)
      }
    }

    // Check immediately
    checkConnection()

    // Set up periodic checks
    const interval = setInterval(checkConnection, 1000)

    return () => clearInterval(interval)
  }, [trpcClient])

  return <IronmonContext.Provider value={{ isConnected }}>{children}</IronmonContext.Provider>
}
