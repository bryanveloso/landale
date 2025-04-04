import { ApiClient } from '@twurple/api'
import { RefreshingAuthProvider, type AuthProvider } from '@twurple/auth'
import { EventSubHttpListener, ReverseProxyAdapter } from '@twurple/eventsub-http'

import { emitEvent } from '..'

const clientId = process.env.TWITCH_CLIENT_ID!
const clientSecret = process.env.TWITCH_CLIENT_SECRET!
const eventSubSecret = process.env.TWITCH_EVENTSUB_SECRET!
const userId = process.env.TWITCH_USER_ID!

const authProvider = new RefreshingAuthProvider({ clientId, clientSecret })

export async function initialize() {
  try {
    const tokenFile = __dirname + '/twitch-token.json'
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
    setupEventListeners(listener, apiClient)
    return listener
  } catch (error) {
    console.error('Error initializing Twitch API:', error)
    throw error
  }
}

function setupEventListeners(listener: EventSubHttpListener, apiClient: ApiClient) {
  listener.onChannelChatMessage(userId, userId, (e) => {
    emitEvent('twitch:message', e)
    console.log('Received message:', e.messageId)
  })
}
