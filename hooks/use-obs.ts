import OBSWebSocket from 'obs-websocket-js'
import { useEffect, useState } from 'react'

const obs = new OBSWebSocket()

export const useObs = () => {
  const [connected, setConnected] = useState<boolean>(false)

  useEffect(() => {
    const init = async () => {
      // Register listeners.
      obs.on('CurrentProgramSceneChanged', data => {
        console.log(`[obs-websocket] New Active Scene: ${data.sceneName}`)
      })

      obs.on('ConnectionError', err => {
        console.error(`[obs-websocket] Socket error: `, err)
      })

      try {
        await obs.connect('ws://localhost:4455', 'yEbNMh47kzPYFf8h')
        console.log(`[obs-websocket] Success! Connected & authenticated.`)
        setConnected(true)
      } catch (e) {
        console.error(`[obs-websocket] Failed to connect`, e.code, e.message)
      }
    }

    init()

    return () => {
      obs.disconnect()
    }
  }, [])

  return {
    connected,
    obs
  }
}
