import { useEffect, useState } from 'react'
import io, { Socket } from 'socket.io-client'

import { Screen } from '@landale/components/screen'
import { getLayout } from '@landale/layouts/for-overlay'

let socket: Socket = io('http://localhost:3000')

export default function Notifier() {
  const [isConnected, setIsConnected] = useState(socket.connected)
  const [lastPong, setLastPong] = useState(null)

  useEffect(() => {
    socket.on('connect', () => {
      setIsConnected(true)
      console.log(`connected`)
    })

    socket.on('disconnect', () => {
      setIsConnected(false)
      console.log(`disconnected`)
    })

    return () => {
      socket.off('connect')
      socket.off('disconnect')
      socket.off('pong')
    }
  }, [])

  const sendPing = () => {
    socket.emit('ping')
  }

  return (
    <div>
      <p>Connected: {'' + isConnected}</p>
    </div>
  )
}

Notifier.getLayout = getLayout
