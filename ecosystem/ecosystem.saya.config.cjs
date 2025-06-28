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
    // Currently all services on saya are managed by Docker
    // This file is kept for future non-Docker services
    // 
    // Example for future services:
    // {
    //   name: 'some-native-service',
    //   script: '/path/to/service',
    //   interpreter: 'none',
    //   error_file: '/opt/landale/logs/service-error.log',
    //   out_file: '/opt/landale/logs/service-out.log'
    // }
  ]
}

