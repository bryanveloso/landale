import {
  app as electron,
  ipcMain,
  nativeTheme,
  BrowserWindow,
  IpcMainEvent
} from 'electron'
import { createServer, IncomingMessage, RequestListener } from 'http'
import next from 'next'
import { loadEnvConfig } from '@next/env'
import { join } from 'path'
import { parse } from 'url'

import { CustomServer, CustomServerResponse } from '../lib'

loadEnvConfig('./', process.env.NODE_ENV !== 'production')

const dev = process.env.NODE_ENV !== 'production'
const hostname = 'localhost'
const port = 8008
const app = next({ dev, hostname, port })
const handle = app.getRequestHandler()
const url = `http://${hostname}:${port}`

// Next.js (Backend and Overlay) Initialization
let server: CustomServer

const listener = async (req: IncomingMessage, res: CustomServerResponse) => {
  try {
    res.server = server

    const parsedUrl = parse(req.url as string, true)
    await handle(req, res, parsedUrl)
  } catch (err) {
    console.error(`Error occured handling`, req.url, err)
    res.statusCode = 500
    res.end('internal server error')
  }
}

const init = async () => {
  await app.prepare()
  server = createServer(listener as RequestListener) as CustomServer
  server.listen(port, () => console.log(`> Ready on ${url}`))
}

// Electron (Dashboard and Controller) Initializiation
const createWindow = async () => {
  await init()
  console.log('Electron will open', url)

  const window = new BrowserWindow({
    backgroundColor: '#1a1d1e',
    minWidth: 720,
    minHeight: 480,
    titleBarStyle: 'hiddenInset',
    webPreferences: {
      nodeIntegration: false,
      preload: join(__dirname, 'preload.js')
    }
  })

  nativeTheme.themeSource = 'system'

  window.loadURL(url)
}

electron.whenReady().then(() => {
  createWindow()
})

electron.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})

electron.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    electron.quit()
  }
})

ipcMain.on('message', (event: IpcMainEvent, message: any) => {
  console.log(message)
  setTimeout(() => event.sender.send('message', message), 500)
})
