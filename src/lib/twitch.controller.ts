import chalk from 'chalk'
import { promises as fs } from 'fs'
import { ApiClient } from '@twurple/api'
import { AccessToken, RefreshingAuthProvider } from '@twurple/auth'
import { ChatClient, ChatMessage } from '@twurple/chat'
import type {
  EventSubChannelGoalType,
  EventSubChannelHypeTrainContribution,
  EventSubChannelHypeTrainContributionType,
  EventSubChannelSubscriptionEventTier,
  EventSubChannelSubscriptionGiftEventTier,
  EventSubChannelSubscriptionMessageEventTier,
  EventSubStreamOnlineEventStreamType,
} from '@twurple/eventsub-base'
import { EventSubWsListener } from '@twurple/eventsub-ws'

import { CustomServer } from './server'

export interface Broadcaster {
  broadcaster_display_name: string
  broadcaster_id: string
  broadcaster_name: string
}

export interface User {
  user_display_name: string
  user_id: string
  user_name: string
}

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
  event: Broadcaster & {
    bits: number
    is_anonymous: boolean
    message: string
    user_display_name: string | null
    user_id: string | null
    user_name: string | null
  }
}

export type TwitchChannelFollowEvent = TwitchEventBase & {
  type: 'channel.follow'
  event: Broadcaster &
    User & {
      follow_date: string
    }
}

export type TwitchChannelGoalBeginEvent = TwitchEventBase & {
  type: 'channel.goal.begin'
  event: Broadcaster & {
    current_amount: number
    description: string
    id: string
    start_date: string
    target_amount: number
    type: EventSubChannelGoalType
  }
}

export type TwitchChannelGoalProgressEvent = TwitchEventBase & {
  type: 'channel.goal.progress'
  event: Broadcaster & {
    current_amount: number
    description: string
    id: string
    start_date: string
    target_amount: number
    type: EventSubChannelGoalType
  }
}

export type TwitchChannelHypeTrainBeginEvent = TwitchEventBase & {
  type: 'channel.hype_train.begin'
  event: Broadcaster & {
    expiry_date: string
    goal: number
    id: string
    last_contribution: EventSubChannelHypeTrainContribution
    level: number
    progress: number
    start_date: string
    top_contributors: EventSubChannelHypeTrainContribution[]
    total: number
  }
}

export type TwitchChannelHypeTrainContribution = TwitchEventBase & {
  type: 'channel.hype_train.contribution'
  event: User & {
    total: number
    type: EventSubChannelHypeTrainContributionType
  }
}

export type TwitchChannelHypeTrainEndEvent = TwitchEventBase & {
  type: 'channel.hype_train.end'
  event: Broadcaster & {
    cooldown_end_date: string
    end_date: string
    id: string
    level: number
    start_date: string
    top_contributors: EventSubChannelHypeTrainContribution[]
    total: number
  }
}

export type TwitchChannelHypeTrainProgressEvent = TwitchEventBase & {
  type: 'channel.hype_train.progress'
  event: Broadcaster & {
    expiry_date: string
    goal: number
    id: string
    last_contribution: EventSubChannelHypeTrainContribution
    level: number
    progress: number
    start_date: string
    top_contributors: EventSubChannelHypeTrainContribution[]
    total: number
  }
}

export type TwitchChannelRaidEvent = TwitchEventBase & {
  type: 'channel.raid'
  event: {
    raided_broadcaster_display_name: string
    raided_broadcaster_id: string
    raided_broadcaster_name: string
    raiding_broadcaster_display_name: string
    raiding_broadcaster_id: string
    raiding_broadcaster_name: string
    viewers: number
  }
}

export type TwitchChannelRedemptionAddEvent = TwitchEventBase & {
  type: 'channel.redemption.add'
  event: Broadcaster &
    User & {
      id: string
      input: string
      redemption_date: string
      reward_cost: number
      reward_id: string
      reward_prompt: string
      reward_title: string
      status: string
    }
}

export type TwitchChannelRedemptionUpdateEvent = TwitchEventBase & {
  type: 'channel.redemption.update'
  event: Broadcaster &
    User & {
      id: string
      input: string
      redemption_date: string
      reward_cost: number
      reward_id: string
      reward_prompt: string
      reward_title: string
      status: string
    }
}

export type TwitchChannelSubscriptionEvent = TwitchEventBase & {
  type: 'channel.subscribe'
  event: Broadcaster &
    User & {
      is_gift: boolean
      tier: EventSubChannelSubscriptionEventTier
    }
}

export type TwitchChannelSubscriptionGiftEvent = TwitchEventBase & {
  type: 'channel.subscription.gift'
  event: Broadcaster & {
    amount: number
    cumulative_amount: number | null
    gifter_display_name: string
    gifter_id: string
    gifter_name: string
    is_anonymous: boolean
    tier: EventSubChannelSubscriptionGiftEventTier
  }
}

export type TwitchChannelSubscriptionMessageEvent = TwitchEventBase & {
  type: 'channel.subscription.message'
  event: Broadcaster &
    User & {
      cumulative_months: number
      duration_months: number
      emote_offsets: Map<string, string[]>
      message_text: string
      streak_months: number | null
      tier: EventSubChannelSubscriptionMessageEventTier
    }
}

export type TwitchChannelUpdateEvent = TwitchEventBase & {
  type: 'channel.update'
  event: Broadcaster & {
    category_id: string
    category_name: string
    is_mature: boolean
    language: string
    title: string
  }
}

export type TwitchStreamOfflineEvent = TwitchEventBase & {
  type: 'stream.offline'
  event: Broadcaster
}

export type TwitchStreamOnlineEvent = TwitchEventBase & {
  type: 'stream.online'
  event: Broadcaster & {
    id: string
    start_date: string
    type: EventSubStreamOnlineEventStreamType
  }
}

export type TwitchEventType =
  | 'channel.cheer'
  | 'channel.follow'
  | 'channel.goal.begin'
  | 'channel.goal.progress'
  | 'channel.hype_train.begin'
  | 'channel.hype_train.end'
  | 'channel.hype_train.progress'
  | 'channel.raid'
  | 'channel.redemption.add'
  | 'channel.redemption.update'
  | 'channel.subscribe'
  | 'channel.subscription.gift'
  | 'channel.subscription.message'
  | 'channel.update'
  | 'stream.offline'
  | 'stream.online'

export type TwitchEvent =
  | TwitchChannelCheerEvent
  | TwitchChannelFollowEvent
  | TwitchChannelGoalBeginEvent
  | TwitchChannelGoalProgressEvent
  | TwitchChannelHypeTrainBeginEvent
  | TwitchChannelHypeTrainEndEvent
  | TwitchChannelHypeTrainProgressEvent
  | TwitchChannelRaidEvent
  | TwitchChannelRedemptionAddEvent
  | TwitchChannelRedemptionUpdateEvent
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
  private server: CustomServer;
  private apiClient?: ApiClient;
  private listener?: EventSubWsListener;
  private callback = process.env.TWITCH_CALLBACK_URL as string;
  private clientId = process.env.TWITCH_CLIENT_ID as string;
  private clientSecret = process.env.TWITCH_CLIENT_SECRET as string;
  private eventsubSecret = process.env.TWITCH_EVENTSUB_SECRET as string;
  private userId = process.env.TWITCH_USER_ID as string;
  username = process.env.TWITCH_USERNAME as string;

  chatClient?: ChatClient;

  constructor(server: CustomServer) {
    this.server = server;

    this.setup();
  }

  setup = async () => {
    await this.setupApiClient();
    await this.setupEventSub();
    await this.setupChatBot();
  };

  setupApiClient = async () => {
    const authProvider = await getAuthProvider();
    this.apiClient = new ApiClient({ authProvider });
  };

  setupEventSub = async () => {
    this.listener = new EventSubWsListener({ apiClient: this.apiClient! });

    this.listener.onChannelCheer(this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.cheer',
        },
        type: 'channel.cheer',
        event: {
          bits: event.bits,
          broadcaster_display_name: event.broadcasterDisplayName,
          broadcaster_id: event.broadcasterId,
          broadcaster_name: event.broadcasterName,
          is_anonymous: event.isAnonymous,
          message: event.message,
          user_display_name: event.userDisplayName || '',
          user_id: event.userId || '',
          user_name: event.userName || '',
        },
      });
    });

    this.listener.onChannelFollow(this.userId, this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.follow',
        },
        type: 'channel.follow',
        event: {
          broadcaster_display_name: event.broadcasterDisplayName,
          broadcaster_id: event.broadcasterId,
          broadcaster_name: event.broadcasterName,
          follow_date: event.followDate.toISOString(),
          user_display_name: event.userDisplayName,
          user_id: event.userId,
          user_name: event.userName,
        },
      });
    });

    this.listener.onChannelGoalBegin(this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.goal.begin',
        },
        type: 'channel.goal.begin',
        event: {
          broadcaster_display_name: event.broadcasterDisplayName,
          broadcaster_id: event.broadcasterId,
          broadcaster_name: event.broadcasterName,
          current_amount: event.currentAmount,
          description: event.description,
          id: event.id,
          start_date: event.startDate.toISOString(),
          target_amount: event.targetAmount,
          type: event.type,
        },
      });
    });

    this.listener.onChannelGoalProgress(this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.goal.progress',
        },
        type: 'channel.goal.progress',
        event: {
          broadcaster_display_name: event.broadcasterDisplayName,
          broadcaster_id: event.broadcasterId,
          broadcaster_name: event.broadcasterName,
          current_amount: event.currentAmount,
          description: event.description,
          id: event.id,
          start_date: event.startDate.toISOString(),
          target_amount: event.targetAmount,
          type: event.type,
        },
      });
    });

    this.listener.onChannelRaidFrom(this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.raid',
        },
        type: 'channel.raid',
        event: {
          raided_broadcaster_display_name: event.raidedBroadcasterDisplayName,
          raided_broadcaster_id: event.raidedBroadcasterId,
          raided_broadcaster_name: event.raidedBroadcasterName,
          raiding_broadcaster_display_name: event.raidingBroadcasterDisplayName,
          raiding_broadcaster_id: event.raidingBroadcasterId,
          raiding_broadcaster_name: event.raidingBroadcasterName,
          viewers: event.viewers,
        },
      });
    });

    // this.listener.onChannelRedemptionAddForReward(this.userId, (event) => { })

    this.listener.onChannelRedemptionUpdate(this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.redemption.update',
        },
        type: 'channel.redemption.update',
        event: {
          broadcaster_display_name: event.broadcasterDisplayName,
          broadcaster_id: event.broadcasterId,
          broadcaster_name: event.broadcasterName,
          id: event.id,
          input: event.input,
          redemption_date: event.redemptionDate.toISOString(),
          reward_cost: event.rewardCost,
          reward_id: event.rewardId,
          reward_prompt: event.rewardPrompt,
          reward_title: event.rewardTitle,
          status: event.status,
          user_display_name: event.userDisplayName,
          user_id: event.userId,
          user_name: event.userName,
        },
      });
    });

    // this.listener.onChannelRedemptionUpdateForReward()

    this.listener.onChannelSubscription(this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.subscribe',
        },
        type: 'channel.subscribe',
        event: {
          broadcaster_display_name: event.broadcasterDisplayName,
          broadcaster_id: event.broadcasterId,
          broadcaster_name: event.broadcasterName,
          is_gift: event.isGift,
          tier: event.tier,
          user_display_name: event.userDisplayName,
          user_id: event.userId,
          user_name: event.userName,
        },
      });
    });

    this.listener.onChannelSubscriptionGift(this.userId, event => {
      this.handleEvent({
        key: '',
        subscription: {
          type: 'channel.subscription.gift',
        },
        type: 'channel.subscription.gift',
        event: {
          amount: event.amount,
          broadcaster_display_name: event.broadcasterDisplayName,
          broadcaster_id: event.broadcasterId,
          broadcaster_name: event.broadcasterName,
          cumulative_amount: event.cumulativeAmount,
          gifter_display_name: event.gifterDisplayName,
          gifter_id: event.gifterId,
          gifter_name: event.gifterName,
          is_anonymous: event.isAnonymous,
          tier: event.tier,
        },
      });
    });

    this.listener.onChannelUpdate(this.userId, event => {
      console.log(JSON.stringify(event, null, 2));
      this.server.emit('update', event);
    });

    this.listener.onStreamOffline(this.userId, () => {
      this.server.emit('offline');
    });

    this.listener.onStreamOnline(this.userId, () => {
      this.server.emit('online');
    });

    this.listener.onUserSocketConnect(event => {
      console.log(` ${chalk.green('✓')} Connected to Twitch EventSub`);
    });

    this.listener.onUserSocketDisconnect(() => {
      console.log(` ${chalk.red('✗')} Disconnected from Twitch EventSub`);
    });
  };

  setupChatBot = async () => {
    const authProvider = await getAuthProvider();
    this.chatClient = new ChatClient({
      authProvider,
      channels: [this.username],
    });

    try {
      this.chatClient.connect();
    } catch (error) {
      console.error(error);
    }

    this.chatClient.onMessage(
      async (
        channel: string,
        user: string,
        message: string,
        msg: ChatMessage
      ) => {
        this.server.emit('new-chat-message', { channel, user, message });
        this.server.socket.emit('twitch-chat-event', {
          channel,
          user,
          message,
          broadcaster: msg.userInfo,
          moderator: msg.userInfo.isMod,
        });
      }
    );
  };

  getToken = async () => {
    const params: Record<string, string> = {
      client_id: this.clientId,
      client_secret: this.clientSecret,
      grant_type: 'client_credentials',
    };

    const formBody = [];
    for (const property in params) {
      const encodedKey = encodeURIComponent(property);
      const encodedValue = encodeURIComponent(params[property]);
      formBody.push(encodedKey + '=' + encodedValue);
    }
    const body = formBody.join('&');

    const response = await fetch('https://id.twitch.tv/oauth2/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      },
      body,
    });

    const { access_token: token } = (await response.json()) as {
      access_token: string;
    };
    return token;
  };

  handleEvent = async (event: TwitchEvent) => {
    this.server.socket.emit('twitch-event', event);

    switch (event.subscription.type) {
      case 'stream.offline':
        this.server.emit('online');
      case 'stream.online':
        this.server.emit('online');
        break;
      case 'channel.update':
        this.server.emit('update', event);

      default:
        break;
    }
  };

  getChannelInfo = async () => {
    return this.apiClient?.channels.getChannelInfoById(this.userId);
  };

  getStreamInfo = async () => {
    return this.apiClient?.streams.getStreamByUserId(this.userId);
  };

  getUserInfo = async () => {
    return this.apiClient?.users.getUserById(this.userId);
  };

  runCommercial = async () => {
    return this.apiClient?.channels.startChannelCommercial(this.userId, 180);
  };
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
