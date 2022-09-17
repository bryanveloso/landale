import { useEffect, useState } from 'react'
import { io, Socket } from 'socket.io-client'

let initialized = false
let socket: Socket | null = null

export const useSocket = () => {
  const [connected, setConnected] = useState(false)

  const init = async () => {
    initialized = true
    socket = io('ws://localhost:8008')
    socket.connect()

    socket.on('connect', () => {
      console.log(`[rykros-websocket] Connected`)
      setConnected(true)
    })

    socket.on('disconnect', () => {
      console.log(`[rykros-websocket] Disconnected`)
      setConnected(false)
    })
  }

  useEffect(() => {
    if (!initialized) init()

    return () => {
      socket?.close()
      initialized = false
      socket = null
      console.log(`[rykros-websocket] Socket closed`)
    }
  }, [])

  return { socket, connected }
}
