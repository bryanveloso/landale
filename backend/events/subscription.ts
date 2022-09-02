import { EventSubListener } from '@twurple/eventsub'
import { broadcast } from '../websockets'
import { toJSON } from './utils'

export const subscriptionEvent = (
  eventSubClient: EventSubListener,
  userId: string
) =>
  eventSubClient.subscribeToChannelSubscriptionEvents(userId, async e => {
    let data = toJSON(e)
    data.userInfo = toJSON(await e.getUser())

    broadcast('event:subscription', data)
    console.log(data)
  })
 