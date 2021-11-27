import {
  app,
  ipcMain,
  nativeTheme,
  BrowserWindow,
  IpcMainEvent
} from 'electron'
import { join } from 'path'
import isDev from 'electron-is-dev'
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

app.on('ready', () => {
  installDevExtensions(isDev)
    .then(() => {
      createWindow()
    })
    .catch(err => {
      console.error('Error while loading devtools extensions', err)
    })
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

const installDevExtensions = async (isDev_: boolean) => {
  if (!isDev_) {
    return []
  }
  const installer = await import('electron-devtools-installer')

  const extensions = ['REACT_DEVELOPER_TOOLS', 'REDUX_DEVTOOLS'] as const
  const forceDownload = Boolean(process.env.UPGRADE_EXTENSIONS)

  return Promise.all(
    extensions.map(name =>
      installer.default(installer[name], {
        forceDownload,
        loadExtensionOptions: { allowFileAccess: true }
      })
    )
  )
}

ipcMain.on('message', (event: IpcMainEvent, message: any) => {
  console.log(message)
  setTimeout(() => event.sender.send('message', message), 500)
})
