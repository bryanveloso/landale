// PM2 ecosystem configuration for zelan (Mac Studio)
// This manages AI/ML services and audio processing

module.exports = {
  apps: [
    {
      name: 'phononmaser',
      script: 'python',
      args: 'src/main.py',
      cwd: '/opt/landale/apps/phononmaser',
      interpreter: 'none',
      env: {
        PYTHONUNBUFFERED: '1',
        PHONONMASER_PORT: '8889'
      },
      error_file: '/opt/landale/logs/phononmaser-error.log',
      out_file: '/opt/landale/logs/phononmaser-out.log',
      merge_logs: true,
      time: true,
      max_restarts: 10,
      min_uptime: '10s'
    },
    {
      name: 'analysis-service',
      script: 'python',
      args: 'src/main.py',
      cwd: '/opt/landale/apps/analysis',
      interpreter: 'none',
      env: {
        PYTHONUNBUFFERED: '1',
        ANALYSIS_PORT: '8890'
      },
      error_file: '/opt/landale/logs/analysis-error.log',
      out_file: '/opt/landale/logs/analysis-out.log',
      merge_logs: true,
      time: true
    },
    {
      name: 'lm-studio',
      script: '/Applications/LM Studio.app/Contents/MacOS/LM Studio',
      interpreter: 'none',
      args: '--headless --port 1234',
      env: {
        // LM Studio environment variables if needed
      },
      error_file: '/opt/landale/logs/lm-studio-error.log',
      out_file: '/opt/landale/logs/lm-studio-out.log',
      merge_logs: true,
      time: true,
      // LM Studio might need manual start initially
      // After first manual config, PM2 can manage it
    }
  ]
}