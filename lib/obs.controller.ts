import EventEmitter from 'events'
import OBSWebSocket, { OBSResponseTypes } from 'obs-websocket-js'

import { logger } from 'logger'

import SocketController from './socket.controller'

export type Scene =
  | '[🎬] Intro'
  | '[🎬] Mac Studio'
  | '[🎬] Outro'
  | '[🎬] PC'
  | '[🎬] Talk'

export type Source =
  | '[🌎] Horizontal Camera'
  | '[🌎] Notifier'
  | '[🌎] Shared Background'
  | '[🌎] Shared Foreground'
  | '[🌎] Vertical Camera'

export default class ObsController extends EventEmitter {
  obs: OBSWebSocket = new OBSWebSocket()
  currentScene: Scene | undefined
  socketController: SocketController

  private async initObsWebSocket() {
    try {
      await this.obs.connect(
        `ws://${process.env.OBS_WEBSOCKET_URL ?? 'localhost'}:4455`,
        'yEbNMh47kzPYFf8h'
      )
      logger.info(`OBS connected and authenticated`)

      const response = await this.obs.call('GetCurrentProgramScene')
      this.currentScene = response.currentProgramSceneName as Scene

      await this.refreshBrowserSource('[🌎] Notifier')
      await this.refreshBrowserSource('[🌎] Shared Background')
      await this.refreshBrowserSource('[🌎] Shared Foreground')
      await this.refreshBrowserSource('[🌎] Horizontal Camera')
      await this.refreshBrowserSource('[🌎] Vertical Camera')
    } catch (error) {
      logger.error(`OBS is not open! Please restart Landale after opening OBS.`)
    }
  }

  constructor(socketController: SocketController) {
    super()

    this.socketController = socketController
    this.initObsWebSocket()
  }

  startStream = async () => {
    return this.obs.call('StartStream')
  }

  endStream = async () => {
    return this.obs.call('StopStream')
  }

  refreshBrowserSource = async (inputName: Source) => {
    return this.obs.call('PressInputPropertiesButton', {
      inputName,
      propertyName: 'refreshnocache'
    })
  }

  setScene = async (sceneName: Scene) => {
    this.currentScene = sceneName
    this.emit('sceneChange', sceneName)

    return this.obs.call('SetCurrentProgramScene', {
      sceneName
    })
  }

  toggleSource = async (
    sceneName: Scene,
    sourceName: Source,
    enabled: boolean
  ) => {
    this.emit('sourceChange', `${sceneName}: ${sourceName}`)

    const response: OBSResponseTypes['GetSceneItemId'] = await this.obs.call(
      'GetSceneItemId',
      { sceneName, sourceName }
    )

    if (response) {
      return this.obs.call('SetSceneItemEnabled', {
        sceneName,
        sceneItemId: response.sceneItemId,
        sceneItemEnabled: enabled
      })
    }
  }
}
