import { EventSubListener } from '@twurple/eventsub'

export const subscriptionEvent = (
  eventSubClient: EventSubListener,
  userId: string
) =>
  eventSubClient.subscribeToChannelSubscriptionEvents(userId, async e => {
    console.log(e)
  })
