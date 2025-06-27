// PM2 configuration for Mac Studio (zelan)
module.exports = {
  apps: [
    {
      name: 'landale-phononmaser',
      script: 'bun',
      args: 'run start',
      cwd: './apps/phononmaser',
      instances: 1,
      exec_mode: 'fork',

      // Memory management (higher for AI workloads)
      max_memory_restart: '4G',

      // Restart behavior
      max_restarts: 10,
      min_uptime: '10s',
      restart_delay: 4000,
      exp_backoff_restart_delay: 100,

      // Logging
      error_file: './logs/phononmaser-error.log',
      out_file: './logs/phononmaser-out.log',
      merge_logs: true,
      time: true,

      // Environment
      env: {
        NODE_ENV: 'production',
        LOG_LEVEL: 'info',
        PHONONMASER_PORT: 8889,
        WHISPER_CPP_PATH: '/usr/local/bin/whisper',
        LM_STUDIO_API_URL: 'http://localhost:1234/v1'
      },
      env_development: {
        NODE_ENV: 'development',
        PHONONMASER_PORT: 8889,
        LOG_LEVEL: 'debug',
        WHISPER_CPP_PATH: '/usr/local/bin/whisper',
        LM_STUDIO_API_URL: 'http://localhost:1234/v1'
      }
    }
  ]
}
