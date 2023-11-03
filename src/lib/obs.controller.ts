import chalk from 'chalk'
import EventEmitter from 'events'
import OBSWebSocket, { OBSResponseTypes } from 'obs-websocket-js'

import SocketController from './socket.controller'

export type Scene = '[🎬] Intro' | '[🎬] Alys' | '[🎬] Words on Stream'

export type Source = '[🌎] Background' | '[🌎] Horizontal Camera'

export default class ObsController extends EventEmitter {
  currentScene: Scene | undefined
  socketController: SocketController
  websocket: OBSWebSocket = new OBSWebSocket()

  private async initObsWebsocket() {
    try {
      const { obsWebSocketVersion, negotiatedRpcVersion } =
        await this.websocket.connect(`ws://127.0.0.1:4455`, 'pVH9gCpaOQniUW6i')

      console.log(
        ` ${chalk.green(
          '✓',
        )} Connected to OBSWebSocket v${obsWebSocketVersion}, (using RPC ${negotiatedRpcVersion})`,
      )

      const response = await this.websocket.call('GetCurrentProgramScene')
      this.currentScene = response.currentProgramSceneName as Scene

      await this.refreshBrowserSource('[🌎] Background')
      await this.refreshBrowserSource('[🌎] Horizontal Camera')
    } catch (error) {
      console.error(error)
    }
  }

  constructor(socketController: SocketController) {
    super()

    this.socketController = socketController
    this.initObsWebsocket()
  }

  refreshBrowserSource = async (inputName: Source) => {
    return this.websocket.call('PressInputPropertiesButton', {
      inputName,
      propertyName: 'refreshnocache',
    })
  }

  setScene = async (sceneName: Scene) => {
    this.currentScene = sceneName
    this.emit('sceneChange', sceneName)

    return this.websocket.call('SetCurrentProgramScene', { sceneName })
  }
}
