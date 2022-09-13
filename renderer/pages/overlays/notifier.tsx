import WebSocket from 'isomorphic-ws'
import { useEffect, useRef, useState } from 'react'

import { Screen } from '@landale/components/screen'
import { getLayout } from '@landale/layouts/for-overlay'

export default function Notifier() {
  const ws = useRef(null)
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    ws.current = new WebSocket('ws://localhost:3000')

    ws.current.onopen = () => {
      console.log(`connected`)
      setIsConnected(true)
    }

    ws.current.onclose = () => {
      console.log(`disconnected`)
      setIsConnected(false)
    }

    return () => {
      ws.current.close()
    }
  }, [])

  useEffect(() => {
    if (!ws.current) return

    ws.current.onmessage = (e: any) => {
      console.log(e)
    }
  })

  return (
    <div>
      <p>Connected: {'' + isConnected}</p>
    </div>
  )
}

Notifier.getLayout = getLayout
