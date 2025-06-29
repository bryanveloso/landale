// PM2 ecosystem configuration for saya (Mac Mini)
// This manages non-Docker services on saya
//
// NOTE: The following services are managed by Docker Compose:
// - landale-server
// - landale-overlays  
// - postgresql
// - seq

module.exports = {
  apps: [
    {
      name: 'pm2-agent',
      script: 'bun',
      args: '/opt/landale/ecosystem/bin/pm2-agent.ts',
      interpreter: 'none',
      env: {
        PM2_AGENT_PORT: 9615,
        PM2_AGENT_HOST: '0.0.0.0',
        PM2_AGENT_TOKEN: process.env.PM2_AGENT_TOKEN || 'change-me-in-production'
      },
      error_file: '/opt/landale/logs/pm2-agent-error.log',
      out_file: '/opt/landale/logs/pm2-agent-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false
    }
  ]
}