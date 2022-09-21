import { NextApiResponseServerIO } from './server'
import TwitchController from './twitch.controller'

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
  }

  init = async () => {
    const info = await this.twitch.getStreamInfo()
    this.streamStartTime = info?.startDate
  }

  handleStreamOnline = async () => {
    await this.init()
  }

  handleStreamOffline = async () => {
    await this.init()
  }
}
