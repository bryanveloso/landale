import { contextBridge, ipcRenderer, IpcRenderer } from 'electron'

// All of the Node.js APIs are available in the preload process.
// It has the same sandbox as a Chrome extension.
window.addEventListener('DOMContentLoaded', () => {
  const replaceText = (selector: string, text: string) => {
    const element = document.getElementById(selector)
    if (element) {
      element.innerText = text
    }
  }

  for (const type of ['chrome', 'node', 'electron']) {
    replaceText(
      `${type}-version`,
      process.versions[type as keyof NodeJS.ProcessVersions]
    )
  }
})

// Since we disabled nodeIntegration, we can reintroduce needed bits
// of node functionality here.
declare global {
  namespace NodeJS {
    interface Global {
      ipcRenderer: IpcRenderer
    }
  }
}

process.once('loaded', () => {
  global.ipcRenderer = ipcRenderer
})

export const electronApiKey = 'landale'

export const electronApi = {
  electronIpcSend: (channel: string, ...arg: any) => {
    ipcRenderer.send(channel, arg)
  },
  electronIpcSendSync: (channel: string, ...arg: any) => {
    return ipcRenderer.sendSync(channel, arg)
  },
  electronIpcOn: (
    channel: string,
    listener: (event: any, ...arg: any) => void
  ) => {
    ipcRenderer.on(channel, listener)
  },
  electronIpcOnce: (
    channel: string,
    listener: (event: any, ...arg: any) => void
  ) => {
    ipcRenderer.once(channel, listener)
  },
  electronIpcRemoveListener: (
    channel: string,
    listener: (event: any, ...arg: any) => void
  ) => {
    ipcRenderer.removeListener(channel, listener)
  },
  electronIpcRemoveAllListeners: (channel: string) => {
    ipcRenderer.removeAllListeners(channel)
  }
}

contextBridge.exposeInMainWorld(electronApiKey, electronApi)
