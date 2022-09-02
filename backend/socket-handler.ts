import express, { Express } from 'express'
import * as http from 'http'
import * as socketio from 'socket.io'

const socketHandler = async () => {
  const port: number = parseInt(process.env.PORT || '8007', 10)
  const app: Express = express()
  const server: http.Server = http.createServer(app)
  const io: socketio.Server = new socketio.Server()

  io.attach(server)
  io.on('connection', (socket: socketio.Socket) => {
    console.log('connection')
    socket.emit('status', 'Hello!')

    socket.on('disconnect', () => {
      console.log('disconnected')
    })
  })

  server.listen(port, () => {
    console.log(`> Ready on http://localhost:${port}`)
  })
}

export default socketHandler
