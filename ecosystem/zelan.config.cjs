// PM2 configuration for Mac Studio (zelan)
module.exports = {
  apps: [
    {
      name: 'landale-phononmaser',
      script: 'python3',
      args: '-m src.main',
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
        LOG_LEVEL: 'info',
        PHONONMASER_PORT: 8889,
        PHONONMASER_HEALTH_PORT: 8890,
        WHISPER_MODEL_PATH: '/usr/local/share/whisper/models/large-v3-turbo.bin',
        WHISPER_THREADS: 8,
        WHISPER_LANGUAGE: 'en'
      },
      env_development: {
        LOG_LEVEL: 'debug',
        PHONONMASER_PORT: 8889,
        PHONONMASER_HEALTH_PORT: 8890,
        WHISPER_MODEL_PATH: '/usr/local/share/whisper/models/large-v3-turbo.bin',
        WHISPER_THREADS: 8,
        WHISPER_LANGUAGE: 'en'
      }
    },
    {
      name: 'landale-analysis',
      script: 'python3',
      args: '-m src.main',
      cwd: './apps/analysis',
      instances: 1,
      exec_mode: 'fork',

      // Memory management
      max_memory_restart: '2G',

      // Restart behavior
      max_restarts: 10,
      min_uptime: '10s',
      restart_delay: 4000,
      exp_backoff_restart_delay: 100,

      // Logging
      error_file: './logs/analysis-error.log',
      out_file: './logs/analysis-out.log',
      merge_logs: true,
      time: true,

      // Environment
      env: {
        LOG_LEVEL: 'info',
        PHONONMASER_URL: 'ws://localhost:8889',
        SERVER_URL: 'ws://localhost:7175/events',
        LMS_API_URL: 'http://localhost:1234/v1',
        LMS_MODEL: 'dolphin-2.9.3-llama-3-8b'
      },
      env_development: {
        LOG_LEVEL: 'debug',
        PHONONMASER_URL: 'ws://localhost:8889',
        SERVER_URL: 'ws://localhost:7175/events',
        LMS_API_URL: 'http://localhost:1234/v1',
        LMS_MODEL: 'dolphin-2.9.3-llama-3-8b'
      }
    }
  ]
}
