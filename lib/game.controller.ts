import { EventEmitter } from 'stream'

import ObsController from './obs.controller'
import { CustomServer } from './server'
import TwitchController from './twitch.controller'

export default class GameController extends EventEmitter {
  private server: CustomServer
  private obs: ObsController
  private twitch: TwitchController

  constructor(
    server: CustomServer,
    obs: ObsController,
    twitch: TwitchController
  ) {
    super()

    this.server = server
    this.obs = obs
    this.twitch = twitch

    this.obs.obs.on('CurrentProgramSceneChanged', scene => {
      console.log('scene', scene)
    })

    this.obs.obs.on('SceneItemEnableStateChanged', args => {
      console.log('item', args)
    })

    this.init()
  }

  init = async () => {}
}
