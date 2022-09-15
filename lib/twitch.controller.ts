import { EventEmitter } from 'stream'
import { ApiClient } from '@twurple/api'
import { ClientCredentialsAuthProvider } from '@twurple/auth'

import { CustomServer } from './server'
import ObsController from './obs.controller'

export default class TwitchController extends EventEmitter {
  private server: CustomServer
  private obs: ObsController
  private apiClient?: ApiClient
  private clientId = process.env.TWITCH_CLIENT_ID as string
  private clientSecret = process.env.TWITCH_CLIENT_SECRET as string

  constructor(server: CustomServer, obs: ObsController) {
    super()

    this.server = server
    this.obs = obs

    this.setup()
  }

  setup = async () => {
    this.setupApiClient()
  }

  setupApiClient = () => {
    const authProvider = getAuthProvider()
    this.apiClient = new ApiClient({ authProvider })
  }
}

export const getAuthProvider = () => {
  const clientId = process.env.TWITCH_CLIENT_ID as string
  const clientSecret = process.env.TWITCH_CLIENT_SECRET as string

  return new ClientCredentialsAuthProvider(clientId, clientSecret)
}
