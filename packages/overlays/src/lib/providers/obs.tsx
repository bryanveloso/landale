import OBSWebSocket from 'obs-websocket-js'
import { type FC, type PropsWithChildren, createContext, useEffect } from 'react'

export const OBSContext = createContext(null)

const socketUrl = 'ws://demi:4455'

export const OBSProvider: FC<PropsWithChildren> = ({ children }) => {
  useEffect(() => {
    const obs = new OBSWebSocket()
    const init = async () => {
      try {
        const { obsWebSocketVersion, negotiatedRpcVersion } = await obs.connect(socketUrl, 'yfX1E3UyKP3gTQ2e')
        console.log(
          `🟢 <OBSContext /> connected. obs-websocket-js: ${obsWebSocketVersion}, rpc: ${negotiatedRpcVersion}`
        )
      } catch (err: unknown) {
        const error = err as Error
        console.error(`🔴 <OBSContext /> failed to connect:`, error.message)
      }
    }

    init()
  }, [])

  return <OBSContext.Provider value={null}>{children}</OBSContext.Provider>
}
