import { ApiClient } from '@twurple/api'
import { RefreshingAuthProvider } from '@twurple/auth'
import { EventSubHttpListener, ReverseProxyAdapter } from '@twurple/eventsub-http'

import { env } from '@/lib/env'
import { emitEvent } from '..'

const clientId = env.TWITCH_CLIENT_ID
const clientSecret = env.TWITCH_CLIENT_SECRET
const eventSubSecret = env.TWITCH_EVENTSUB_SECRET
const userId = env.TWITCH_USER_ID

const authProvider = new RefreshingAuthProvider({ clientId, clientSecret })

export async function initialize() {
  try {
    const tokenFile = `${__dirname}/twitch-token.json`
    const tokenData = await Bun.file(tokenFile).json()

    authProvider.onRefresh(async (_, newTokenData) => {
      await Bun.write(tokenFile, JSON.stringify(newTokenData, null, 4))
    })

    await authProvider.addUserForToken(tokenData, ['chat'])

    const apiClient = new ApiClient({ authProvider })
    const listener = new EventSubHttpListener({
      apiClient,
      secret: eventSubSecret,
      adapter: new ReverseProxyAdapter({
        hostName: 'twitch.veloso.house',
        port: 8081
      })
    })

    listener.start()
    setupEventListeners(listener)
    return listener
  } catch (error) {
    console.error('Error initializing Twitch API:', error)
    throw error
  }
}

const setupEventListeners = async (listener: EventSubHttpListener) => {
  // Channel cheer subscription
  listener.onChannelCheer(userId, (e) => {
    console.log('Received cheer:', e)
    emitEvent('twitch:cheer', {
      bits: e.bits,
      isAnonymous: e.isAnonymous,
      message: e.message,
      userDisplayName: e.userDisplayName,
      userId: e.userId,
      userName: e.userName
    })
  })

  // Channel message subscription
  listener.onChannelChatMessage(userId, userId, (e) => {
    console.log('Received message:', e.messageId)
    emitEvent('twitch:message', {
      badges: e.badges,
      bits: e.bits,
      chatterDisplayName: e.chatterDisplayName,
      chatterId: e.chatterId,
      chatterName: e.chatterName,
      color: e.color,
      isCheer: e.isCheer,
      isRedemption: e.isRedemption,
      messageId: e.messageId,
      messageParts: e.messageParts,
      messageText: e.messageText,
      messageType: e.messageType,
      parentMessageId: e.parentMessageId,
      parentMessageText: e.parentMessageText,
      parentMessageUserDisplayName: e.parentMessageUserDisplayName,
      parentMessageUserId: e.parentMessageUserId,
      parentMessageUserName: e.parentMessageUserName,
      rewardId: e.rewardId,
      threadMessageId: e.threadMessageId,
      threadMessageUserDisplayName: e.threadMessageUserDisplayName,
      threadMessageUserId: e.threadMessageUserId,
      threadMessageUserName: e.threadMessageUserName
    })
  })
}
