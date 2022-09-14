import { useEffect, useRef, useState } from 'react'
import { io, Socket } from 'socket.io-client'

import { Screen } from '@landale/components/screen'
import { getLayout } from '@landale/layouts/for-overlay'

export default function Notifier() {
  const ws = useRef<Socket>(null)
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    ws.current = io('ws://localhost:3000')

    ws.current.on('connect', () => {
      console.log(`[rykros-websocket] Connected`)
      setIsConnected(true)
    })

    ws.current.on('disconnect', () => {
      console.log(`[rykros-websocket] Disconnected`)
      setIsConnected(false)
    })

    return () => {
      ws.current.off('connect')
      ws.current.off('disconnect')
    }
  }, [])

  useEffect(() => {
    if (!ws.current) return

    ws.current.on('notification', (e: any) => {
      console.log(e)
    })

    return () => {
      ws.current.off('notification')
    }
  }, [])

  return (
    <div>
      <p>Connected: {'' + isConnected}</p>
    </div>
  )
}

Notifier.getLayout = getLayout
