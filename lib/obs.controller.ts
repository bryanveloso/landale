import EventEmitter from 'events'
import OBSWebSocket from 'obs-websocket-js'

import SocketController from './socket.controller'

export type Scene = '[🎬] Intro' | '[🎬] Talk'

export default class ObsController extends EventEmitter {
  obs = new OBSWebSocket()
  currentScene: Scene | undefined
  socketController: SocketController

  private async initObsWebSocket() {
    await this.obs.connect('ws://localhost:4455', 'yEbNMh47kzPYFf8h')
    console.log(`[ObsController] Connected and authenticated`)

    const response = await this.obs.call('GetCurrentProgramScene')
    this.currentScene = response.currentProgramSceneName as Scene
  }

  constructor(socketController: SocketController) {
    super()

    this.socketController = socketController
    this.initObsWebSocket()
  }
}
