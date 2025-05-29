import type { 
  EventSubChannelChatMessageEvent, 
  EventSubChannelCheerEvent,
  EventSubChannelFollowEvent,
  EventSubChannelSubscriptionEvent,
  EventSubChannelSubscriptionGiftEvent,
  EventSubChannelSubscriptionMessageEvent,
  EventSubChannelRedemptionAddEvent,
  EventSubStreamOnlineEvent,
  EventSubStreamOfflineEvent
} from '@twurple/eventsub-base'

export interface TwitchEvent {
  cheer: Partial<EventSubChannelCheerEvent>
  message: Partial<EventSubChannelChatMessageEvent>
  follow: Partial<EventSubChannelFollowEvent>
  subscription: Partial<EventSubChannelSubscriptionEvent>
  subscriptionGift: Partial<EventSubChannelSubscriptionGiftEvent>
  subscriptionMessage: Partial<EventSubChannelSubscriptionMessageEvent>
  redemption: Partial<EventSubChannelRedemptionAddEvent>
  streamOnline: Partial<EventSubStreamOnlineEvent>
  streamOffline: Partial<EventSubStreamOfflineEvent>
}
