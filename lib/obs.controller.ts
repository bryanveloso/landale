import EventEmitter from 'events'
import OBSWebSocket from 'obs-websocket-js'

import { logger } from 'logger'

import SocketController from './socket.controller'

export type Scene = '[🎬] Intro' | '[🎬] Talk'

export type Source = '[🌎] Notifier'

export default class ObsController extends EventEmitter {
  obs = new OBSWebSocket()
  currentScene: Scene | undefined
  socketController: SocketController

  private async initObsWebSocket() {
    await this.obs.connect('ws://localhost:4455', 'yEbNMh47kzPYFf8h')
    logger.info(`[ObsController] Connected and authenticated`)

    const response = await this.obs.call('GetCurrentProgramScene')
    this.currentScene = response.currentProgramSceneName as Scene

    await this.refreshBrowserSource('[🌎] Notifier')
  }

  constructor(socketController: SocketController) {
    super()

    this.socketController = socketController
    this.initObsWebSocket()
  }

  async endStream() {
    return this.obs.call('StopStream')
  }

  async refreshBrowserSource(inputName: Source) {
    return this.obs.call('PressInputPropertiesButton', {
      inputName,
      propertyName: 'refreshnocache'
    })
  }

  async setScene(sceneName: Scene) {
    this.currentScene = sceneName
    this.emit('sceneChange', sceneName)

    return this.obs.call('SetCurrentProgramScene', {
      sceneName
    })
  }
}
