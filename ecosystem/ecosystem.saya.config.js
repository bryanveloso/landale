// PM2 ecosystem configuration for saya (Mac Mini)
// This manages the core Landale services

module.exports = {
  apps: [
    {
      name: 'landale-server',
      script: 'bun',
      args: 'run src/index.ts',
      cwd: '/opt/landale/apps/server',
      interpreter: 'none',
      env: {
        NODE_ENV: 'production',
        PORT: 7175,
        DATABASE_URL: 'postgresql://landale:landale@localhost:5432/landale'
      },
      error_file: '/opt/landale/logs/server-error.log',
      out_file: '/opt/landale/logs/server-out.log',
      merge_logs: true,
      time: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false,
      instances: 1,
      exec_mode: 'fork'
    },
    {
      name: 'landale-overlays',
      script: 'bun',
      args: 'run build && bunx serve -s dist -l 8008',
      cwd: '/opt/landale/apps/overlays',
      interpreter: 'none',
      env: {
        NODE_ENV: 'production',
        PORT: 8008
      },
      error_file: '/opt/landale/logs/overlays-error.log',
      out_file: '/opt/landale/logs/overlays-out.log',
      merge_logs: true,
      time: true
    },
    // Note: Docker services (PostgreSQL, Seq) are managed separately
    // via docker-compose and not through PM2
  ]
}