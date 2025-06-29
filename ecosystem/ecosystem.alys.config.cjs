// PM2 ecosystem configuration for alys (Windows Gaming Machine)
// Handles gaming applications

module.exports = {
  apps: [
    {
      name: 'streamer-bot',
      script: 'D:\\Utilities\\Streamer.Bot\\Streamer.Bot.exe',
      interpreter: 'none',
      cwd: 'D:\\Utilities\\Streamer.Bot',
      env: {},
      error_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\streamer-bot-error.log',
      out_file: 'C:\\Users\\Avalonstar\\AppData\\Local\\Landale\\logs\\streamer-bot-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: false,
      max_restarts: 10,
      min_uptime: '30s',
      watch: false,
      windowsHide: false
    },
    {
      name: 'pm2-agent',
      script: 'node',
      args: '.\\ecosystem\\bin\\pm2-agent.js',
      interpreter: 'none',
      cwd: '.\\ecosystem\\bin',
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
