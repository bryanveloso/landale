import chalk from 'chalk'
import { promises as fs } from 'fs'
import { ApiClient, HelixEventSubSubscription } from '@twurple/api'
import {
  AccessToken,
  RefreshingAuthProvider,
  TokenInfoData,
} from '@twurple/auth'
import { ChatClient, ChatMessage } from '@twurple/chat'
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
  EventSubStreamOnlineEvent,
} from '@twurple/eventsub-base'
import { EventSubWsListener } from '@twurple/eventsub-ws'

import ObsController from './obs.controller'
import { CustomServer } from './server'

// Because Twurple's Data types are private, we have to use this to filter out the functions.
// Reference: https://stackoverflow.com/questions/55479658/how-to-create-a-type-excluding-instance-methods-from-a-class-in-typescript
type NonFunctionPropertyNames<T> = {
  [K in keyof T]: T[K] extends Function ? never : K
}[keyof T]

type NonFunctionProperties<T> = Pick<T, NonFunctionPropertyNames<T>>

export interface TwitchChatEvent {
  channel: string
  user: string
  message: string
  broadcaster: boolean
  moderator: boolean
}

export interface TwitchEventBase {
  key: string
  subscription: {
    type: TwitchEventType
  }
}

export type TwitchChannelCheerEvent = TwitchEventBase & {
  type: 'channel.cheer'
  event: NonFunctionProperties<EventSubChannelCheerEvent>
}

export type TwitchChannelFollowEvent = TwitchEventBase & {
  type: 'channel.follow'
  event: NonFunctionProperties<EventSubChannelFollowEvent>
}

export type TwitchChannelHypeTrainBeginEvent = TwitchEventBase & {
  type: 'channel.hype_train.begin'
  event: NonFunctionProperties<EventSubChannelHypeTrainBeginEvent>
}

export type TwitchChannelHypeTrainEndEvent = TwitchEventBase & {
  type: 'channel.hype_train.end'
  event: NonFunctionProperties<EventSubChannelHypeTrainEndEvent>
}

export type TwitchChannelHypeTrainProgressEvent = TwitchEventBase & {
  type: 'channel.hype_train.progress'
  event: NonFunctionProperties<EventSubChannelHypeTrainProgressEvent>
}

export type TwitchChannelRaidEvent = TwitchEventBase & {
  type: 'channel.raid'
  event: NonFunctionProperties<EventSubChannelRaidEvent>
}

export type TwitchChannelSubscriptionEvent = TwitchEventBase & {
  type: 'channel.subscribe'
  event: Omit<
    NonFunctionProperties<EventSubChannelSubscriptionEvent>,
    '[rawDataSymbol]'
  >
}

export type TwitchChannelSubscriptionGiftEvent = TwitchEventBase & {
  type: 'channel.subscription.gift'
  event: NonFunctionProperties<EventSubChannelSubscriptionGiftEvent>
}

export type TwitchChannelSubscriptionMessageEvent = TwitchEventBase & {
  type: 'channel.subscription.message'
  event: NonFunctionProperties<EventSubChannelSubscriptionMessageEvent>
}

export type TwitchChannelUpdateEvent = TwitchEventBase & {
  type: 'channel.update'
  event: NonFunctionProperties<EventSubChannelUpdateEvent>
}

export type TwitchStreamOfflineEvent = TwitchEventBase & {
  type: 'stream.offline'
  event: NonFunctionProperties<EventSubStreamOfflineEvent>
}

export type TwitchStreamOnlineEvent = TwitchEventBase & {
  type: 'stream.online'
  event: NonFunctionProperties<EventSubStreamOnlineEvent>
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

export interface TwitchEventSubscription {
  id: string
  status:
    | 'enabled'
    | 'webhook_callback_verification_pending'
    | 'webhook_callback_verification_failed'
    | 'notification_failures_exceeded'
    | 'authorization_revoked'
    | 'user_removed'
  type: string
  version: string
  condition: { broadcaster_user_id: string }
  created_at: string
  transport: {
    method: 'webhook'
    callback: string
  }
  cost: number
}

export default class TwitchController {
  private server: CustomServer
  private obs: ObsController
  private apiClient?: ApiClient
  private listener?: EventSubWsListener
  private callback = process.env.TWITCH_CALLBACK_URL as string
  private clientId = process.env.TWITCH_CLIENT_ID as string
  private clientSecret = process.env.TWITCH_CLIENT_SECRET as string
  private eventsubSecret = process.env.TWITCH_EVENTSUB_SECRET as string
  private userId = process.env.TWITCH_USER_ID as string
  username = process.env.TWITCH_USERNAME as string

  chatClient?: ChatClient

  constructor(server: CustomServer, obs: ObsController) {
    this.obs = obs
    this.server = server

    this.setup()
  }

  setup = async () => {
    await this.setupApiClient()
    await this.setupEventSub()
    await this.setupChatBot()
  }

  setupApiClient = async () => {
    const authProvider = await getAuthProvider()
    this.apiClient = new ApiClient({ authProvider })
  }

  setupEventSub = async () => {
    this.listener = new EventSubWsListener({
      apiClient: this.apiClient!,
    })

    this.listener.onChannelCheer(this.userId, (event) => {})

    this.listener.onChannelFollow(this.userId, this.userId, (event) => {})

    this.listener.onChannelGoalBegin(this.userId, (event) => {})

    this.listener.onChannelGoalProgress(this.userId, (event) => {})

    this.listener.onChannelRaidFrom(this.userId, (event) => {})

    // this.listener.onChannelRedemptionAddForReward()

    this.listener.onChannelRedemptionUpdate(this.userId, (event) => {})

    // this.listener.onChannelRedemptionUpdateForReward()

    // Channel Subscription
    this.listener.onChannelSubscription(this.userId, (event) => {})

    this.listener.onChannelSubscriptionGift(this.userId, (event) => {})

    this.listener.onChannelUpdate(this.userId, (event) => {})

    this.listener.onStreamOffline(this.userId, () => {
      this.server.emit('offline')
    })

    this.listener.onStreamOnline(this.userId, () => {
      this.server.emit('online')
    })

    this.listener.onUserSocketConnect(() => {
      console.log(` ${chalk.green('✓')} Connected to Twitch EventSub`)
    })

    this.listener.onUserSocketDisconnect(() => {
      console.log(` ${chalk.red('✗')} Disconnected from Twitch EventSub`)
    })

    this.listener.start()

    // const token = await this.getToken()
    // const subscriptions = await listSubscriptions({
    //   token,
    //   clientId: this.clientId,
    // })
    // const eventTypes: [TwitchEventType, object?][] = [
    //   ['channel.cheer'],
    //   ['channel.follow'],
    //   ['channel.hype_train.begin'],
    //   ['channel.hype_train.end'],
    //   ['channel.hype_train.progress'],
    //   ['channel.raid', { to_broadcaster_user_id: this.userId }],
    //   ['channel.subscribe'],
    //   ['channel.subscription.gift'],
    //   ['channel.subscription.message'],
    //   ['channel.update'],
    //   ['stream.online'],
    //   ['stream.online'],
    // ]
    // for (const [eventType, condition] of eventTypes) {
    //   const existing = subscriptions.find((sub) => sub.type === eventType)
    //   if (
    //     existing &&
    //     (existing.status === 'enabled' ||
    //       existing.status === 'webhook_callback_verification_pending')
    //   ) {
    //     continue
    //   }

    //   if (existing) {
    //     await deleteSubscription({
    //       subscription: existing,
    //       token,
    //       clientId: this.clientId,
    //     })
    //   }

    //   await createSubscription({
    //     token,
    //     clientId: this.clientId,
    //     type: eventType,
    //     webhookSecret: this.eventsubSecret,
    //     callback: this.callback,
    //     condition: condition ?? { broadcaster_user_id: this.userId },
    //   })
    // }
  }

  setupChatBot = async () => {
    const authProvider = await getAuthProvider()
    this.chatClient = new ChatClient({
      authProvider,
      channels: [this.username],
    })

    try {
      this.chatClient.connect()
    } catch (error) {
      console.error(error)
    }

    this.chatClient.onMessage(
      async (
        channel: string,
        user: string,
        message: string,
        msg: ChatMessage
      ) => {
        this.server.emit('new-chat-message', { channel, user, message })
        this.server.socket.emit('twitch-chat-event', {
          channel,
          user,
          message,
          broadcaster: msg.userInfo,
          moderator: msg.userInfo.isMod,
        })
      }
    )
  }

  getToken = async () => {
    const params: Record<string, string> = {
      client_id: this.clientId,
      client_secret: this.clientSecret,
      grant_type: 'client_credentials',
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
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      },
      body,
    })

    const { access_token: token } = (await response.json()) as {
      access_token: string
    }
    return token
  }

  handleEvent = async (event: TwitchEvent) => {
    this.server.socket.emit('twitch-event', event)

    switch (event.subscription.type) {
      case 'stream.offline':
        this.server.emit('online')
      case 'stream.online':
        this.server.emit('online')
        break
      case 'channel.update':
        this.server.emit('update', event)

      default:
        break
    }
  }

  getChannelInfo = async () => {
    return this.apiClient?.channels.getChannelInfoById(this.userId)
  }

  getStreamInfo = async () => {
    return this.apiClient?.streams.getStreamByUserId(this.userId)
  }

  getUserInfo = async () => {
    return this.apiClient?.users.getUserById(this.userId)
  }

  runCommercial = async () => {
    return this.apiClient?.channels.startChannelCommercial(this.userId, 180)
  }
}

const listSubscriptions = async ({
  token,
  clientId,
}: {
  token: string
  clientId: string
}) => {
  const subscriptions = await fetch(
    'https://api.twitch.tv/helix/eventsub/subscriptions',
    {
      headers: {
        Authorization: `Bearer ${token}`,
        'Client-Id': clientId,
      },
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
  clientId,
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
        'Client-Id': clientId,
      },
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
  webhookSecret: secret,
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
      secret,
    },
  })

  try {
    const subscription = await fetch(
      'https://api.twitch.tv/helix/eventsub/subscriptions',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Client-Id': clientId,
          'Content-Type': 'application/json',
        },
        body,
      }
    )

    const response = await subscription.json()
    return response
  } catch (error) {
    console.error(error)
  }
}

export const getAuthProvider = async () => {
  const clientId = process.env.TWITCH_CLIENT_ID as string
  const clientSecret = process.env.TWITCH_CLIENT_SECRET as string
  const userId = process.env.TWITCH_USER_ID as string

  const tokenData = JSON.parse(
    await fs.readFile(`./tokens.${userId}.json`, 'utf-8')
  )
  const provider = new RefreshingAuthProvider({
    clientId,
    clientSecret,
  })

  provider.onRefresh(
    async (userId: string, newTokenData: AccessToken) =>
      await fs.writeFile(
        `./tokens.${userId}.json`,
        JSON.stringify(newTokenData, null, 4),
        'utf-8'
      )
  )

  provider.addUser(userId, tokenData, ['chat'])
  return provider
}
