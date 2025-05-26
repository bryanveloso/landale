import { FC, PropsWithChildren, createContext, useContext } from 'react'
import { useIronmonSubscription } from '@/lib/hooks/use-ironmon'

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
  // Initialize IronMON subscriptions
  useIronmonSubscription()

  // TODO: Add connection status tracking
  const isConnected = true

  return (
    <IronmonContext.Provider value={{ isConnected }}>
      {children}
    </IronmonContext.Provider>
  )
}