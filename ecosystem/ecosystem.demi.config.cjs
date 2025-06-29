// PM2 ecosystem configuration for demi (Windows OBS Machine)
// Handles OBS and streaming software

module.exports = {
  apps: [
    {
      name: 'obs-studio',
      script: 'C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe',
      args: '--enable-media-stream',
      exec_mode: 'fork',
      instances: 1,
      cwd: 'C:\\Program Files\\obs-studio\\bin\\64bit',
      env: {},
      error_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\obs-error.log',
      out_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\obs-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: false,
      min_uptime: '30s',
      watch: false,
      max_restarts: 0,
      windowsHide: false
    },
    {
      name: 'vtube-studio',
      script: 'D:\\Steam\\steamapps\\common\\VTube Studio\\VTube Studio.exe',
      exec_mode: 'fork',
      instances: 1,
      cwd: 'D:\\Steam\\steamapps\\common\\VTube Studio',
      env: {},
      error_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\vts-error.log',
      out_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\vts-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: false,
      min_uptime: '30s',
      watch: false,
      windowsHide: false
    },
    {
      name: 'tits',
      script: 'D:\\Applications\\TITS\\TITS Launcher.exe',
      exec_mode: 'fork',
      instances: 1,
      cwd: 'D:\\Applications\\TITS',
      env: {},
      error_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\tits-error.log',
      out_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\tits-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: false,
      min_uptime: '30s',
      watch: false,
      windowsHide: false
    },
    {
      name: 'pm2-agent',
      script: 'bun',
      args: 'C:\\Users\\Avalonstar\\Code\\Landale\\ecosystem\\bin\\pm2-agent.js',
      interpreter: 'none',
      cwd: 'C:\\Users\\Avalonstar\\Code\\Landale',
      env: {
        PM2_AGENT_PORT: 9615,
        PM2_AGENT_HOST: '0.0.0.0',
        PM2_AGENT_TOKEN: process.env.PM2_AGENT_TOKEN || 'change-me-in-production'
      },
      error_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\pm2-agent-error.log',
      out_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\pm2-agent-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false
    }
  ]
}
