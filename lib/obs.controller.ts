import EventEmitter from 'events'
import OBSWebSocket, { OBSResponseTypes } from 'obs-websocket-js'

import { logger } from 'logger'

import SocketController from './socket.controller'

export type Scene =
  | '[🎬] Intro'
  | '[🎬] Mac Studio'
  | '[🎬] Outro'
  | '[🎬] Talk'
  | '[🎮] IronMON'
  | '[🎮] PC'

export type Source =
  | '[🌎] Intro'
  | '[🌎] Horizontal Camera'
  | '[🌎] IronMON Tracker'
  | '[🌎] Notifier'
  | '[🌎] Shared Background'
  | '[🌎] Shared Foreground'
  | '[🌎] Vertical Camera'

export default class ObsController extends EventEmitter {
  websocket: OBSWebSocket = new OBSWebSocket()
  currentScene: Scene | undefined
  socketController: SocketController

  private async initObsWebSocket() {
    try {
      await this.websocket.connect(
        `ws://${process.env.OBS_WEBSOCKET_URL ?? 'localhost'}:4455`,
        'yEbNMh47kzPYFf8h'
      )
      logger.info(`OBS connected and authenticated`)

      const response = await this.websocket.call('GetCurrentProgramScene')
      this.currentScene = response.currentProgramSceneName as Scene

      await this.refreshBrowserSource('[🌎] Intro')
      await this.refreshBrowserSource('[🌎] IronMON Tracker')
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
    return this.websocket.call('StartStream')
  }

  endStream = async () => {
    return this.websocket.call('StopStream')
  }

  refreshBrowserSource = async (inputName: Source) => {
    return this.websocket.call('PressInputPropertiesButton', {
      inputName,
      propertyName: 'refreshnocache'
    })
  }

  setScene = async (sceneName: Scene) => {
    this.currentScene = sceneName
    this.emit('sceneChange', sceneName)

    return this.websocket.call('SetCurrentProgramScene', {
      sceneName
    })
  }

  toggleSource = async (
    sceneName: Scene,
    sourceName: Source,
    enabled: boolean
  ) => {
    this.emit('sourceChange', `${sceneName}: ${sourceName}`)

    const response: OBSResponseTypes['GetSceneItemId'] =
      await this.websocket.call('GetSceneItemId', { sceneName, sourceName })

    if (response) {
      return this.websocket.call('SetSceneItemEnabled', {
        sceneName,
        sceneItemId: response.sceneItemId,
        sceneItemEnabled: enabled
      })
    }
  }
}
