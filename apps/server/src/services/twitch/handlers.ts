import { ApiClient } from '@twurple/api'
import { RefreshingAuthProvider, type AccessToken } from '@twurple/auth'
import { EventSubWsListener } from '@twurple/eventsub-ws'

import { env } from '@/lib/env'
import { createLogger } from '@landale/logger'

import { emitEvent } from '@/events'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'twitch' })

const clientId = env.TWITCH_CLIENT_ID
const clientSecret = env.TWITCH_CLIENT_SECRET
const userId = env.TWITCH_USER_ID

const authProvider = new RefreshingAuthProvider({ clientId, clientSecret })

export async function initialize() {
  try {
    const tokenFile = `${__dirname}/twitch-token.json`
    const tokenData = (await Bun.file(tokenFile).json()) as AccessToken

    authProvider.onRefresh((_, newTokenData) => {
      void Bun.write(tokenFile, JSON.stringify(newTokenData, null, 4))
    })

    await authProvider.addUserForToken(tokenData, ['chat'])

    const apiClient = new ApiClient({ authProvider })

    // Clean up broken subscriptions to avoid hitting limits
    log.info('Cleaning up broken EventSub subscriptions')
    await apiClient.eventSub.deleteBrokenSubscriptions()
    log.info('Subscription cleanup completed')

    const listener = new EventSubWsListener({ apiClient })

    // Add error handler to prevent retries on subscription failures
    listener.onSubscriptionDeleteFailure((error) => {
      log.warn('Subscription deletion failed', { error: new Error(JSON.stringify(error)) })
    })

    listener.start()
    setupEventListeners(listener)
    return listener
  } catch (error) {
    log.error('Error initializing Twitch API', { error: error as Error })
    throw error
  }
}

const setupEventListeners = (listener: EventSubWsListener) => {
  // Channel cheer subscription
  listener.onChannelCheer(userId, (e) => {
    log.debug('Received cheer', {
      metadata: { bits: e.bits, userDisplayName: e.userDisplayName }
    })
    void emitEvent('twitch:cheer', {
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
    log.debug('Received message', {
      metadata: { chatterDisplayName: e.chatterDisplayName, messageText: e.messageText }
    })
    void emitEvent('twitch:message', {
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

  // Channel follow subscription
  listener.onChannelFollow(userId, userId, (e) => {
    log.info('New follower', { metadata: { userDisplayName: e.userDisplayName } })
    void emitEvent('twitch:follow', {
      userId: e.userId,
      userName: e.userName,
      userDisplayName: e.userDisplayName,
      followDate: e.followDate
    })
  })

  // Channel subscription
  listener.onChannelSubscription(userId, (e) => {
    log.info('New subscription', {
      metadata: { userDisplayName: e.userDisplayName, tier: e.tier }
    })
    void emitEvent('twitch:subscription', {
      userId: e.userId,
      userName: e.userName,
      userDisplayName: e.userDisplayName,
      tier: e.tier,
      isGift: e.isGift
    })
  })

  // Channel subscription gift
  listener.onChannelSubscriptionGift(userId, (e) => {
    log.info('Gift subscription', {
      metadata: {
        gifterDisplayName: e.gifterDisplayName,
        amount: e.amount,
        recipient: e.isAnonymous ? 'anonymous users' : 'the community'
      }
    })
    void emitEvent('twitch:subscription:gift', {
      gifterId: e.gifterId,
      gifterName: e.gifterName,
      gifterDisplayName: e.gifterDisplayName,
      isAnonymous: e.isAnonymous,
      amount: e.amount,
      cumulativeAmount: e.cumulativeAmount,
      tier: e.tier
    })
  })

  // Channel subscription message (resub)
  listener.onChannelSubscriptionMessage(userId, (e) => {
    log.info('Resub', {
      metadata: { userDisplayName: e.userDisplayName, cumulativeMonths: e.cumulativeMonths }
    })
    void emitEvent('twitch:subscription:message', {
      userId: e.userId,
      userName: e.userName,
      userDisplayName: e.userDisplayName,
      tier: e.tier,
      messageText: e.messageText,
      cumulativeMonths: e.cumulativeMonths,
      durationMonths: e.durationMonths,
      streakMonths: e.streakMonths
    })
  })

  // Channel point redemption
  listener.onChannelRedemptionAdd(userId, (e) => {
    log.info('Channel point redemption', {
      metadata: { userDisplayName: e.userDisplayName, rewardTitle: e.rewardTitle }
    })
    void emitEvent('twitch:redemption', {
      id: e.id,
      userId: e.userId,
      userName: e.userName,
      userDisplayName: e.userDisplayName,
      rewardId: e.rewardId,
      rewardTitle: e.rewardTitle,
      rewardCost: e.rewardCost,
      input: e.input,
      status: e.status,
      redemptionDate: e.redemptionDate
    })
  })

  // Stream online
  listener.onStreamOnline(userId, (e) => {
    log.info('Stream went online', {
      metadata: { broadcasterDisplayName: e.broadcasterDisplayName, type: e.type }
    })
    void emitEvent('twitch:stream:online', {
      id: e.id,
      broadcasterId: e.broadcasterId,
      broadcasterName: e.broadcasterName,
      broadcasterDisplayName: e.broadcasterDisplayName,
      type: e.type,
      startDate: e.startDate
    })
  })

  // Stream offline
  listener.onStreamOffline(userId, (e) => {
    log.info('Stream went offline', {
      metadata: { broadcasterDisplayName: e.broadcasterDisplayName }
    })
    void emitEvent('twitch:stream:offline', {
      broadcasterId: e.broadcasterId,
      broadcasterName: e.broadcasterName,
      broadcasterDisplayName: e.broadcasterDisplayName
    })
  })
}
