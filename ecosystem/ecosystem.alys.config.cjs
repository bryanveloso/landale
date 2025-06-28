// PM2 ecosystem configuration for alys (Windows - Gaming PC)
// This manages streaming and gaming applications

module.exports = {
  apps: [
    // Game launchers - optional, add as needed
    {
      name: 'steam',
      script: 'C:\\Program Files (x86)\\Steam\\steam.exe',
      interpreter: 'none',
      args: '-silent',
      cwd: 'C:\\Program Files (x86)\\Steam',
      // Use AppData for logs - better practice than polluting C:\
      error_file: process.env.APPDATA + '\\landale\\logs\\steam-error.log',
      out_file: process.env.APPDATA + '\\landale\\logs\\steam-out.log',
      merge_logs: true,
      time: true,
      autorestart: false
    }
  ]
}
