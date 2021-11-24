import { app, ipcMain, BrowserWindow, IpcMainEvent } from 'electron'
import { join } from 'path'
import prepareNext from 'electron-next'

const createWindow = async () => {
  await prepareNext('./renderer', 8008)

  const window = new BrowserWindow({
    width: 800,
    height: 600,
    webPreferences: {
      nodeIntegration: false,
      preload: join(__dirname, 'preload.js')
    }
  })

  const url = 'http://localhost:8008/'
  window.loadURL(url)
}

app.on('ready', () => {
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
