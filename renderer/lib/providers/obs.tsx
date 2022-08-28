import OBSWebSocket, { EventSubscription } from 'obs-websocket-js'
import { createContext, useContext, useEffect, useState, FC } from 'react'

type ContextTypes = {
  isOBSConnected: boolean
}

export const OBSContext = createContext<ContextTypes>(undefined!)

export const OBSProvider: FC = ({ children }) => {
  const [isOBSConnected, setIsOBSConnected] = useState(false)

  useEffect(() => {
    const obs = new OBSWebSocket()
    const connect = async () => {
      await obs.connect('ws://localhost:4455', 'yEbNMh47kzPYFf8h')
      console.log(`[obs-websocket] Success! Connected & authenticated.`)
      setIsOBSConnected(true)
    }

    try {
      connect()
    } catch (e) {
      console.error(e)
    }

    // Register listeners.
    obs.on('CurrentProgramSceneChanged', data => {
      console.log(`[obs-websocket] New Active Scene: ${data['scene-name']}`)
    })

    return () => {
      obs.disconnect()
    }
  }, [])

  return (
    <OBSContext.Provider value={{ isOBSConnected }}>
      {children}
    </OBSContext.Provider>
  )
}

export const useOBS = () => useContext(OBSContext)
