import type { Server } from 'bun';
import { ApiClient } from '@twurple/api';
import { RefreshingAuthProvider, type AuthProvider } from '@twurple/auth';
import { ChatClient } from '@twurple/chat';
import {
  EventSubHttpListener,
  ReverseProxyAdapter,
} from '@twurple/eventsub-http';
import { PubSubClient } from '@twurple/pubsub';

const clientId = process.env.TWITCH_CLIENT_ID!;
const clientSecret = process.env.TWITCH_CLIENT_SECRET!;
const eventSubSecret = process.env.TWITCH_EVENTSUB_SECRET!;
const authProvider = new RefreshingAuthProvider({ clientId, clientSecret });

const setupChat = async (authProvider: AuthProvider) => {
  const chatClient = new ChatClient({ authProvider, channels: ['avalonstar'] });
  chatClient.connect();

  chatClient.onConnect(() => {
    console.log('Connected to chat');
  });
};

const setupEventSub = async (apiClient: ApiClient) => {
  const listener = new EventSubHttpListener({
    apiClient,
    secret: eventSubSecret,
    adapter: new ReverseProxyAdapter({
      hostName: 'twitch.veloso.house',
      port: 8081,
    }),
  });

  listener.start();
};

const setupPubSub = async (authProvider: AuthProvider) => {
  const pubSubClient = new PubSubClient({ authProvider });
};

export const init = async (wss: Server): Promise<void> => {
  const tokenFile = __dirname + '/twitch-token.json';
  const tokenData = await Bun.file(tokenFile).json();

  authProvider.onRefresh(async (_, newTokenData) => {
    await Bun.write(tokenFile, JSON.stringify(newTokenData, null, 4));
  });

  await authProvider.addUserForToken(tokenData, ['chat']);

  const apiClient = new ApiClient({ authProvider });

  await setupChat(authProvider);
  await setupEventSub(apiClient);
  await setupPubSub(authProvider);
};
