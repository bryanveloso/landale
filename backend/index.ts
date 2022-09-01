import eventHandler from './event-handler'
import 'dotenv/config'

const { TWITCH_CHANNEL } = process.env
console.log('TWITCH_CHANNEL', TWITCH_CHANNEL)

eventHandler()
