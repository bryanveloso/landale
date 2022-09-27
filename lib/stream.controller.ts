import { NextApiResponseServerIO } from './server'
import TwitchController from './twitch.controller'

export const getChannelInfo = async (res: NextApiResponseServerIO) => {
  const channel = await res.server.twitch.getChannelInfo()
  return channel
}

export const getUserInfo = async (res: NextApiResponseServerIO) => {
  const user = await res.server.twitch.getUserInfo()
  return user
}

export const getStreamInfo = async (res: NextApiResponseServerIO) => {
  const stream = await res.server.twitch.getStreamInfo()
  return stream
}

export default class StreamController {
  private streamStartTime?: Date
  private twitch: TwitchController

  constructor(twitch: TwitchController) {
    this.twitch = twitch
    const [today] = new Date().toISOString().split('T')

    this.twitch.on('online', this.handleStreamOnline.bind(this))
    this.twitch.on('offline', this.handleStreamOffline.bind(this))

    this.init()
  }

  init = async () => {
    const info = await this.twitch.getStreamInfo()
    // this.streamStartTime = info?.startDate
  }

  handleStreamOnline = async () => {
    await this.init()
  }

  handleStreamOffline = async () => {
    await this.init()
  }
}
