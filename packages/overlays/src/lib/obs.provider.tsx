import OBSWebSocket from 'obs-websocket-js'
import { type FC, type PropsWithChildren, createContext, useEffect, useMemo } from 'react'

export const OBSContext = createContext(null)

const socketUrl = 'ws://demi.local:4455'

export const OBSProvider: FC<PropsWithChildren> = ({ children }) => {
  const obs = useMemo(() => new OBSWebSocket(), [])

  useEffect(() => {
    const init = async () => {
      try {
        const { obsWebSocketVersion, negotiatedRpcVersion } = await obs.connect(socketUrl, 'pVH9gCpaOQniUW6i', {
          rpcVersion: 1
        })
        console.log(
          `🟢 <OBSContext /> connected. obs-websocket-js: ${obsWebSocketVersion}, rpc: ${negotiatedRpcVersion}`
        )
      } catch (error) {
        console.error(`🔴 <OBSContext /> failed to connect:`, error)
      }
    }

    init()
  }, [obs])

  return <OBSContext.Provider value={null}>{children}</OBSContext.Provider>
}
