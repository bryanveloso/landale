import eventHandler from './event-handler'
import io from './websockets'
import 'dotenv/config'

const { PORT } = process.env

//
eventHandler()

//
const wsPort = parseInt(PORT || '80')
io.listen(wsPort)
