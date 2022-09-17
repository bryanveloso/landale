import { promises as fs, readFileSync } from 'fs'
import { EventEmitter } from 'stream'
import { ApiClient, HelixEventSubSubscription } from '@twurple/api'
import { RefreshingAuthProvider } from '@twurple/auth'
import { ChatClient, PrivateMessage } from '@twurple/chat'
import type {
  EventSubChannelCheerEvent,
  EventSubChannelFollowEvent,
  EventSubChannelHypeTrainBeginEvent,
  EventSubChannelHypeTrainEndEvent,
  EventSubChannelHypeTrainProgressEvent,
  EventSubChannelRaidEvent,
  EventSubChannelSubscriptionEvent,
  EventSubChannelSubscriptionGiftEvent,
  EventSubChannelSubscriptionMessageEvent,
  EventSubChannelUpdateEvent,
  EventSubStreamOfflineEvent,
  EventSubStreamOnlineEvent
} from '@twurple/eventsub'

import { CustomServer } from './server'
import ObsController from './obs.controller'
import { logger } from 'logger'

export interface TwitchEventBase {
  key: string
  subscription: {
    id: string
    status: 'enabled' | 'disabled'
    type: TwitchEventType
    version: '1'
    created_at: string
  }
}

export type TwitchChannelCheerEvent = TwitchEventBase & {
  type: 'channel.cheer'
  event: EventSubChannelCheerEvent
}

export type TwitchChannelFollowEvent = TwitchEventBase & {
  type: 'channel.follow'
  event: EventSubChannelFollowEvent
}

export type TwitchChannelHypeTrainBeginEvent = TwitchEventBase & {
  type: 'channel.hype_train.begin'
  event: EventSubChannelHypeTrainBeginEvent
}

export type TwitchChannelHypeTrainEndEvent = TwitchEventBase & {
  type: 'channel.hype_train.end'
  event: EventSubChannelHypeTrainEndEvent
}

export type TwitchChannelHypeTrainProgressEvent = TwitchEventBase & {
  type: 'channel.hype_train.progress'
  event: EventSubChannelHypeTrainProgressEvent
}

export type TwitchChannelRaidEvent = TwitchEventBase & {
  type: 'channel.raid'
  event: EventSubChannelRaidEvent
}

export type TwitchChannelSubscriptionEvent = TwitchEventBase & {
  type: 'channel.subscribe'
  event: EventSubChannelSubscriptionEvent
}

export type TwitchChannelSubscriptionGiftEvent = TwitchEventBase & {
  type: 'channel.subscription.gift'
  event: EventSubChannelSubscriptionGiftEvent
}

export type TwitchChannelSubscriptionMessageEvent = TwitchEventBase & {
  type: 'channel.subscription.message'
  event: EventSubChannelSubscriptionMessageEvent
}

export type TwitchChannelUpdateEvent = TwitchEventBase & {
  type: 'channel.update'
  event: EventSubChannelUpdateEvent
}

export type TwitchStreamOfflineEvent = TwitchEventBase & {
  type: 'stream.offline'
  event: EventSubStreamOfflineEvent
}

export type TwitchStreamOnlineEvent = TwitchEventBase & {
  type: 'stream.online'
  event: EventSubStreamOnlineEvent
}

export type TwitchEventType =
  | 'channel.cheer'
  | 'channel.follow'
  | 'channel.hype_train.begin'
  | 'channel.hype_train.end'
  | 'channel.hype_train.progress'
  | 'channel.raid'
  | 'channel.subscribe'
  | 'channel.subscription.gift'
  | 'channel.subscription.message'
  | 'channel.update'
  | 'stream.offline'
  | 'stream.online'

export type TwitchEvent =
  | TwitchChannelCheerEvent
  | TwitchChannelFollowEvent
  | TwitchChannelHypeTrainBeginEvent
  | TwitchChannelHypeTrainEndEvent
  | TwitchChannelHypeTrainProgressEvent
  | TwitchChannelRaidEvent
  | TwitchChannelSubscriptionEvent
  | TwitchChannelSubscriptionGiftEvent
  | TwitchChannelSubscriptionMessageEvent
  | TwitchChannelUpdateEvent
  | TwitchStreamOfflineEvent
  | TwitchStreamOnlineEvent

export default class TwitchController extends EventEmitter {
  private server: CustomServer
  private obs: ObsController
  private apiClient?: ApiClient
  private callback = process.env.TWITCH_CALLBACK_URL as string
  private clientId = process.env.TWITCH_CLIENT_ID as string
  private clientSecret = process.env.TWITCH_CLIENT_SECRET as string
  private eventsubSecret = process.env.TWITCH_EVENTSUB_SECRET as string
  private userId = process.env.TWITCH_USER_ID as string
  username = process.env.TWITCH_USERNAME as string

  chatClient?: ChatClient

  constructor(server: CustomServer, obs: ObsController) {
    super()

    this.server = server
    this.obs = obs

    this.setup()
  }

  setup = async () => {
    this.setupApiClient()
    await this.setupEventSub()
    await this.setupChatBot()
  }

  setupApiClient = () => {
    const authProvider = getAuthProvider()
    this.apiClient = new ApiClient({ authProvider })
  }

  setupEventSub = async () => {
    const token = await this.getToken()

    const subscriptions = await listSubscriptions({
      token,
      clientId: this.clientId
    })
    console.log(subscriptions)
    const eventTypes: [TwitchEventType, object?][] = [
      ['channel.cheer'],
      ['channel.follow'],
      ['channel.hype_train.begin'],
      ['channel.hype_train.end'],
      ['channel.hype_train.progress'],
      ['channel.raid', { to_broadcaster_user_id: this.userId }],
      ['channel.subscribe'],
      ['channel.subscription.gift'],
      ['channel.subscription.message'],
      ['channel.update'],
      ['stream.online'],
      ['stream.online']
    ]
    for (const [eventType, condition] of eventTypes) {
      const existing = subscriptions.find(sub => sub.type === eventType)
      if (
        existing &&
        (existing.status === 'enabled' ||
          existing.status === 'webhook_callback_verification_pending')
      ) {
        continue
      }

      if (existing) {
        await deleteSubscription({
          subscription: existing,
          token,
          clientId: this.clientId
        })
      }

      await createSubscription({
        token,
        clientId: this.clientId,
        type: eventType,
        webhookSecret: this.eventsubSecret,
        callback: this.callback,
        condition: condition ?? { broadcaster_user_id: this.userId }
      })
    }
  }

  setupChatBot = async () => {
    const authProvider = getAuthProvider()
    this.chatClient = new ChatClient({
      authProvider,
      channels: [this.username]
    })

    try {
      await this.chatClient.connect()
    } catch (error) {
      logger.error(error)
    }

    this.chatClient.onMessage(
      async (
        channel: string,
        user: string,
        message: string,
        msg: PrivateMessage
      ) => {
        this.emit('new-chat-message', { channel, user, message })

        this.server.socket.emit('twitch-chat-event', {
          channel,
          user,
          message,
          broadcaster: msg.userInfo.isBroadcaster,
          moderator: msg.userInfo.isMod
        })
      }
    )
  }

  getToken = async () => {
    const params: Record<string, string> = {
      client_id: this.clientId,
      client_secret: this.clientSecret,
      grant_type: 'client_credentials'
    }

    const formBody = []
    for (const property in params) {
      const encodedKey = encodeURIComponent(property)
      const encodedValue = encodeURIComponent(params[property])
      formBody.push(encodedKey + '=' + encodedValue)
    }
    const body = formBody.join('&')

    const response = await fetch('https://id.twitch.tv/oauth2/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'
      },
      body
    })

    const { access_token: token } = (await response.json()) as {
      access_token: string
    }
    return token
  }

  handleEvent = async (event: TwitchEvent) => {
    switch (event.subscription.type) {
      case 'stream.offline':
        this.emit('online')
      case 'stream.online':
        this.emit('online')
        break

      default:
        break
    }
  }
}

export const getAuthProvider = () => {
  const clientId = process.env.TWITCH_CLIENT_ID as string
  const clientSecret = process.env.TWITCH_CLIENT_SECRET as string
  const tokenData = JSON.parse(readFileSync('./tokens.json', 'utf-8'))

  return new RefreshingAuthProvider(
    {
      clientId,
      clientSecret,
      onRefresh: async newTokenData =>
        await fs.writeFile(
          './tokens.json',
          JSON.stringify(newTokenData, null, 4),
          'utf-8'
        )
    },
    tokenData
  )
}

const listSubscriptions = async ({
  token,
  clientId
}: {
  token: string
  clientId: string
}) => {
  const subscriptions = await fetch(
    'https://api.twitch.tv/helix/eventsub/subscriptions',
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'Client-Id': clientId
      }
    }
  )

  const { data } = (await subscriptions.json()) as {
    data: HelixEventSubSubscription[]
  }
  return data
}

const deleteSubscription = async ({
  subscription,
  token,
  clientId
}: {
  subscription: HelixEventSubSubscription
  token: string
  clientId: string
}) => {
  const { id } = subscription
  const response = await fetch(
    `https://api.twitch.tv/helix/eventsub/subscriptions?id=${id}`,
    {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${token}`,
        'Client-Id': clientId
      }
    }
  )

  return response
}

const createSubscription = async ({
  token,
  clientId,
  type,
  condition,
  callback,
  webhookSecret: secret
}: {
  token: string
  clientId: string
  type: TwitchEventType
  condition: unknown
  callback: string
  webhookSecret: string
}) => {
  const body = JSON.stringify({
    type,
    version: '1',
    condition,
    transport: {
      method: 'webhook',
      callback,
      secret
    }
  })

  try {
    const subscription = await fetch(
      'https://api.twitch.tv/helix/eventsub/subscriptions',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Client-Id': clientId,
          'Content-Type': 'application/json'
        },
        body
      }
    )

    const response = await subscription.json()
    return response
  } catch (error) {
    console.error(error)
  }
}
