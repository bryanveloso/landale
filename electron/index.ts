import { join } from 'path'
import {
  app,
  ipcMain,
  nativeTheme,
  BrowserWindow,
  IpcMainEvent
} from 'electron'
import prepareNext from 'electron-next'

const url = 'http://localhost:8008/'
console.log('Electron will open', url)

const createWindow = async () => {
  await prepareNext('./renderer', 8008)

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

app.whenReady().then(() => {
  createWindow()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

ipcMain.on('message', (event: IpcMainEvent, message: any) => {
  console.log(message)
  setTimeout(() => event.sender.send('message', message), 500)
})
