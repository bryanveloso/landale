import { ApiClient } from '@twurple/api'
import { RefreshingAuthProvider } from '@twurple/auth'
import { EventSubWsListener } from '@twurple/eventsub-ws'

import { env } from '@/lib/env'
import { createLogger } from '@/lib/logger'

import { emitEvent } from '@/events'

const logger = createLogger('twitch')

const clientId = env.TWITCH_CLIENT_ID
const clientSecret = env.TWITCH_CLIENT_SECRET
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

    // Clean up broken subscriptions to avoid hitting limits
    logger.info('Cleaning up broken EventSub subscriptions...')
    await apiClient.eventSub.deleteBrokenSubscriptions()
    logger.info('Subscription cleanup completed.')

    const listener = new EventSubWsListener({ apiClient })

    // Add error handler to prevent retries on subscription failures
    listener.onSubscriptionDeleteFailure((error) => {
      logger.warn('Subscription deletion failed', error)
    })

    listener.start()
    setupEventListeners(listener)
    return listener
  } catch (error) {
    logger.error('Error initializing Twitch API.', error)
    throw error
  }
}

const setupEventListeners = async (listener: EventSubWsListener) => {
  // Channel cheer subscription
  listener.onChannelCheer(userId, (e) => {
    logger.debug(`Received cheer: ${e.bits} bits from ${e.userDisplayName}`)
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
    logger.debug(`Received message from ${e.chatterDisplayName}: ${e.messageText}`)
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

  // Channel follow subscription
  listener.onChannelFollow(userId, userId, (e) => {
    logger.info(`New follower: ${e.userDisplayName}`)
    emitEvent('twitch:follow', {
      userId: e.userId,
      userName: e.userName,
      userDisplayName: e.userDisplayName,
      followDate: e.followDate
    })
  })

  // Channel subscription
  listener.onChannelSubscription(userId, (e) => {
    logger.info(`New subscription: ${e.userDisplayName} (${e.tier})`)
    emitEvent('twitch:subscription', {
      userId: e.userId,
      userName: e.userName,
      userDisplayName: e.userDisplayName,
      tier: e.tier,
      isGift: e.isGift
    })
  })

  // Channel subscription gift
  listener.onChannelSubscriptionGift(userId, (e) => {
    logger.info(
      `Gift subscription: ${e.gifterDisplayName} gifted ${e.amount} to ${e.isAnonymous ? 'anonymous users' : 'the community'}`
    )
    emitEvent('twitch:subscription:gift', {
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
    logger.info(`Resub: ${e.userDisplayName} (${e.cumulativeMonths} months)`)
    emitEvent('twitch:subscription:message', {
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
    logger.info(`Channel point redemption: ${e.userDisplayName} redeemed "${e.rewardTitle}"`)
    emitEvent('twitch:redemption', {
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
    logger.info(`Stream went online: ${e.broadcasterDisplayName} playing ${e.type}`)
    emitEvent('twitch:stream:online', {
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
    logger.info(`Stream went offline: ${e.broadcasterDisplayName}`)
    emitEvent('twitch:stream:offline', {
      broadcasterId: e.broadcasterId,
      broadcasterName: e.broadcasterName,
      broadcasterDisplayName: e.broadcasterDisplayName
    })
  })
}
