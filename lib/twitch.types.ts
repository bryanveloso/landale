export type { EventSubChannelCheerEventData } from '@twurple/eventsub/lib/events/EventSubChannelCheerEvent'
export type { EventSubChannelFollowEventData } from '@twurple/eventsub/lib/events/EventSubChannelFollowEvent'
export type { EventSubChannelHypeTrainBeginEventData } from '@twurple/eventsub/lib/events/EventSubChannelHypeTrainBeginEvent'
export type { EventSubChannelHypeTrainEndEventData } from '@twurple/eventsub/lib/events/EventSubChannelHypeTrainEndEvent'
export type { EventSubChannelHypeTrainProgressEventData } from '@twurple/eventsub/lib/events/EventSubChannelHypeTrainProgressEvent'
export type { EventSubChannelRaidEventData } from '@twurple/eventsub/lib/events/EventSubChannelRaidEvent'
export type { EventSubChannelSubscriptionEventData } from '@twurple/eventsub/lib/events/EventSubChannelSubscriptionEvent'
export type { EventSubChannelSubscriptionGiftEventData } from '@twurple/eventsub/lib/events/EventSubChannelSubscriptionGiftEvent'
export type { EventSubChannelSubscriptionMessageEventData } from '@twurple/eventsub/lib/events/EventSubChannelSubscriptionMessageEvent'
export type { EventSubChannelUpdateEventData } from '@twurple/eventsub/lib/events/EventSubChannelUpdateEvent'
export type { EventSubStreamOfflineEventData } from '@twurple/eventsub/lib/events/EventSubStreamOfflineEvent'
export type { EventSubStreamOnlineEventData } from '@twurple/eventsub/lib/events/EventSubStreamOnlineEvent'

export type HelixChannelRawDataObject = {
  broadcaster_id: string
  broadcaster_login: string
  broadcaster_name: string
  broadcaster_language: 'en'
  game_id: string
  game_name: string
  title: string
  delay: number
}
