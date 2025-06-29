// PM2 ecosystem configuration for zelan (Mac Studio)
// This manages AI/ML services and audio processing

module.exports = {
  apps: [
    {
      name: 'phononmaser',
      script: '/Users/Avalonstar/Code/bryanveloso/landale/apps/phononmaser/.venv/bin/python',
      args: '-m src.main',
      cwd: '/Users/Avalonstar/Code/bryanveloso/landale/apps/phononmaser',
      interpreter: 'none',
      env: {
        PYTHONUNBUFFERED: '1',
        LOG_LEVEL: 'info',
        PHONONMASER_PORT: '8889',
        PHONONMASER_HEALTH_PORT: '8890',
        WHISPER_MODEL_PATH: '/Users/Avalonstar/Code/utilities/whisper.cpp/models/ggml-large-v3-turbo-q8_0.bin',
        WHISPER_THREADS: '8',
        WHISPER_LANGUAGE: 'en',
        WHISPER_VAD_MODEL_PATH: '/Users/Avalonstar/Code/utilities/whisper.cpp/models/ggml-silero-v5.1.2.bin',
        SERVER_HOST: 'saya',
        PHONONMASER_HOST: 'zelan',
        SERVER_URL: 'ws://saya:7175/events'
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
      script: '/Users/Avalonstar/Code/bryanveloso/landale/apps/analysis/.venv/bin/python',
      args: '-m src.main',
      cwd: '/Users/Avalonstar/Code/bryanveloso/landale/apps/analysis',
      interpreter: 'none',
      env: {
        PYTHONUNBUFFERED: '1',
        LOG_LEVEL: 'info',
        SERVER_HOST: 'saya',
        PHONONMASER_HOST: 'zelan',
        LMS_HOST: 'zelan',
        ANALYSIS_HOST: 'zelan',
        PHONONMASER_URL: 'ws://zelan:8889',
        SERVER_URL: 'ws://saya:7175/events',
        LMS_API_URL: 'http://zelan:1234/v1',
        LMS_MODEL: 'dolphin-2.9.3-llama-3-8b'
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
      name: 'lms',
      script: 'lms',
      args: ['server', 'start', '--port', '1234'],
      interpreter: 'none',
      env: {},
      error_file: '/Users/Avalonstar/Library/Logs/Landale/lms-error.log',
      out_file: '/Users/Avalonstar/Library/Logs/Landale/lms-out.log',
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
