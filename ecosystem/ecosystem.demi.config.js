// PM2 ecosystem configuration for demi (Windows - Gaming/OBS PC)
// This manages streaming and gaming applications

module.exports = {
  apps: [
    {
      name: 'obs-studio',
      script: 'C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe',
      interpreter: 'none',
      args: '--minimize-to-tray --multi',
      cwd: 'C:\\Program Files\\obs-studio\\bin\\64bit',
      error_file: 'C:\\landale\\logs\\obs-error.log',
      out_file: 'C:\\landale\\logs\\obs-out.log',
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
      script: 'C:\\Program Files\\VTube Studio\\VTube Studio.exe',
      interpreter: 'none',
      cwd: 'C:\\Program Files\\VTube Studio',
      error_file: 'C:\\landale\\logs\\vtube-error.log',
      out_file: 'C:\\landale\\logs\\vtube-out.log',
      merge_logs: true,
      time: true,
      autorestart: false
    },
    {
      name: 'streamlabs-desktop',
      script: 'C:\\Program Files\\Streamlabs Desktop\\Streamlabs Desktop.exe',
      interpreter: 'none',
      cwd: 'C:\\Program Files\\Streamlabs Desktop',
      error_file: 'C:\\landale\\logs\\streamlabs-error.log',
      out_file: 'C:\\landale\\logs\\streamlabs-out.log',
      merge_logs: true,
      time: true,
      autorestart: false,
      // Only include if you use Streamlabs
      // Can be managed separately from OBS
    },
    // Game launchers - optional, add as needed
    {
      name: 'steam',
      script: 'C:\\Program Files (x86)\\Steam\\steam.exe',
      interpreter: 'none',
      args: '-silent',
      cwd: 'C:\\Program Files (x86)\\Steam',
      error_file: 'C:\\landale\\logs\\steam-error.log',
      out_file: 'C:\\landale\\logs\\steam-out.log',
      merge_logs: true,
      time: true,
      autorestart: false
    }
  ]
}