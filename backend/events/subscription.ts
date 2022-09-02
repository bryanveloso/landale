import { EventSubListener } from '@twurple/eventsub'
import { broadcast } from '../websockets'

export const subscriptionEvent = (
  eventSubClient: EventSubListener,
  userId: string
) =>
  eventSubClient.subscribeToChannelSubscriptionEvents(userId, async e => {
    console.log(e)
    broadcast('event:subscription')
  })
