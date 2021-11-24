import { app, BrowserWindow } from 'electron'
import { nextStart } from 'next/dist/cli/next-start'
import * as path from 'path'

const createWindow = () => {
  // Create the browser window.
  const mainWindow = new BrowserWindow({
    height: 600,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js')
    },
    width: 800
  })

  // and load the index.html of the app.
  mainWindow.loadFile(path.join(__dirname, '../index.html'))
  // nextStart(['/overlays'])

  // const url = 'http://localhost:3000/'

  // mainWindow.loadURL(url)
}

app.on('ready', () => {
  createWindow()

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})
