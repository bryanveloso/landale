import { EventSubListener } from '@twurple/eventsub'

export const followEvent = (eventSubClient: EventSubListener, userId: string) =>
  eventSubClient.subscribeToChannelFollowEvents(userId, e => {
    console.log(e)
  })
