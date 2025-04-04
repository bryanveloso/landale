import type { EventSubChannelChatMessageEvent } from '@twurple/eventsub-base'

export interface TwitchEvent {
  message: EventSubChannelChatMessageEvent
}
