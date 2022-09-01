import { getEventSubClient } from './clients'
import { events } from './events'
import 'dotenv/config'

const userId = process.env.TWITCH_BROADCASTER_ID ?? ''

const eventHandler = async () => {
  const eventSubClient = await getEventSubClient()
  await eventSubClient.listen()
  for (const event of events) {
    const eventListener = await event(eventSubClient, userId)
    const testCommand = await eventListener.getCliTestCommand()
    console.log(testCommand)
  }
}

export default eventHandler
