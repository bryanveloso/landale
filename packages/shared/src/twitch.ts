/**
 * Shared Twitch types used by both server and overlay packages
 */

export interface TwitchMessagePart {
  type: 'text' | 'emote' | 'cheer'
  text: string
  emote?: {
    id: string
    name: string
  }
  amount?: number
}

export interface TwitchMessage {
  messageId: string
  messageText: string
  messageParts: TwitchMessagePart[]
  chatterId: string
  chatterName: string
  chatterDisplayName: string
  color?: string
  badges?: Record<string, string>
  isCheer: boolean
  isRedemption: boolean
  bits?: number
}

export interface TwitchCheer {
  userName: string
  userDisplayName: string
  userId: string
  isAnonymous: boolean
  message?: string
  bits: number
}
