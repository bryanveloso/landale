// PM2 ecosystem configuration for demi (Windows - OBS PC)
// This manages streaming and gaming applications

module.exports = {
  apps: [
    {
      name: 'obs-studio',
      script: 'C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe',
      interpreter: 'none',
      args: '--minimize-to-tray --multi',
      cwd: 'C:\\Program Files\\obs-studio\\bin\\64bit',
      // Use AppData for logs - better practice than polluting C:\
      error_file: process.env.APPDATA + '\\landale\\logs\\obs-error.log',
      out_file: process.env.APPDATA + '\\landale\\logs\\obs-out.log',
      merge_logs: true,
      time: true,
      // OBS should not auto-restart if closed intentionally
      autorestart: false,
      // But should restart if it crashes
      max_restarts: 3,
      min_uptime: '30s'
    },
    {
      name: 'vtube-studio',
      script: 'D:\\Steam\\steamapps\\common\\VTube Studio\\VTube Studio.exe',
      interpreter: 'none',
      cwd: 'D:\\Steam\\steamapps\\common\\VTube Studio',
      error_file: process.env.APPDATA + '\\landale\\logs\\vts-error.log',
      out_file: process.env.APPDATA + '\\landale\\logs\\vts-out.log',
      merge_logs: true,
      time: true,
      autorestart: false
    }
  ]
}

