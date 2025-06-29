// PM2 ecosystem configuration for zelan (Mac Studio)
// This manages AI/ML services and audio processing

module.exports = {
  apps: [
    {
      name: 'phononmaser',
      script: 'python',
      args: 'run.py',
      cwd: '/Users/Avalonstar/Code/landale/apps/phononmaser',
      interpreter: 'none',
      env: {
        PYTHONUNBUFFERED: '1',
        PHONONMASER_PORT: '8889'
      },
      error_file: '/Users/Avalonstar/Library/Logs/Landale/phononmaser-error.log',
      out_file: '/Users/Avalonstar/Library/Logs/Landale/phononmaser-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false
    },
    {
      name: 'analysis',
      script: 'python',
      args: '-m src.main',
      cwd: '/Users/Avalonstar/Code/landale/apps/analysis',
      interpreter: 'none',
      env: {
        PYTHONUNBUFFERED: '1',
        ANALYSIS_PORT: '8890'
      },
      error_file: '/Users/Avalonstar/Library/Logs/Landale/analysis-error.log',
      out_file: '/Users/Avalonstar/Library/Logs/Landale/analysis-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false
    },
    {
      name: 'lm-studio',
      script: '/Applications/LM Studio.app/Contents/MacOS/LM Studio',
      interpreter: 'none',
      args: '--headless --port 1234',
      env: {
      },
      error_file: '/Users/Avalonstar/Library/Logs/Landale/lm-studio-error.log',
      out_file: '/Users/Avalonstar/Library/Logs/Landale/lm-studio-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: false,
      max_restarts: 5,
      min_uptime: '30s',
      watch: false
    },
    {
      name: 'pm2-agent',
      script: 'bun',
      args: './ecosystem/bin/pm2-agent.ts',
      interpreter: 'none',
      env: {
        PM2_AGENT_PORT: 9615,
        PM2_AGENT_HOST: '0.0.0.0',
        PM2_AGENT_TOKEN: process.env.PM2_AGENT_TOKEN || 'change-me-in-production'
      },
      error_file: '/Users/Avalonstar/Library/Logs/Landale/pm2-agent-error.log',
      out_file: '/Users/Avalonstar/Library/Logs/Landale/pm2-agent-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false
    }
  ]
}
