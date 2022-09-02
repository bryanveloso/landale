import { EventSubListener } from '@twurple/eventsub'

import { broadcast } from '../websockets'

import { toJSON } from './utils'

export const followEvent = (eventSubClient: EventSubListener, userId: string) =>
  eventSubClient.subscribeToChannelFollowEvents(userId, async e => {
    let data = toJSON(e)
    data.userInfo = toJSON(await e.getUser())

    broadcast('event:follow', data)
    console.log(data)
  })
