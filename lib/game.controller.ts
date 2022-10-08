import { EventSubChannelUpdateEvent } from '@twurple/eventsub/lib'
import { EventEmitter } from 'stream'

import ObsController from './obs.controller'
import { CustomServer } from './server'
import TwitchController, { TwitchChannelUpdateEvent } from './twitch.controller'

export type Game =
  | 'Destiny 2'
  | 'Final Fantasy XIV'
  | 'Genshin Impact'
  | 'Path of Exile'
  | 'Pokémon FireRed/LeafGreen'
  | string

export default class GameController extends EventEmitter {
  private server: CustomServer
  private obs: ObsController
  private twitch: TwitchController

  private initGameController() {
    this.twitch.on('update', (event: TwitchChannelUpdateEvent) => {
      const gameName = event.event.category_name as Game

      switch (gameName) {
        case 'Destiny 2':
          this.switchToDestiny()
          break
        case 'Pokémon FireRed/LeafGreen':
          this.switchToIronMON()
          break

        default:
          break
      }
    })
  }

  constructor(
    server: CustomServer,
    obs: ObsController,
    twitch: TwitchController
  ) {
    super()

    this.server = server
    this.obs = obs
    this.twitch = twitch

    this.initGameController()
  }

  switchToDestiny = async () => {
    this.obs.setScene('[🎮] PC')
  }

  switchToFFXIV = async () => {
    this.obs.setScene('[🎮] PC')
  }

  switchToIronMON = async () => {
    this.obs.setScene('[🎮] IronMON')
  }
}
