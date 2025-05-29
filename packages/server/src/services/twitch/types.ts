import type { EventSubChannelChatMessageEvent, EventSubChannelCheerEvent } from '@twurple/eventsub-base'

export interface TwitchEvent {
  cheer: Partial<EventSubChannelCheerEvent>
  message: Partial<EventSubChannelChatMessageEvent>
}
