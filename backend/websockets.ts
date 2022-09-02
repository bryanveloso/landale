import * as socketio from 'socket.io'

const io = new socketio.Server({
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
})

io.on('connection', (socket: socketio.Socket) => {
  console.log(`New connection: ${socket.id}`)
})

export const broadcast = (message: string, content?: any) => {
  console.log('broadcasting', message)
  io.local.emit(message, content)
}

export default io
