import { z } from 'zod'

// Service configuration schema
const ServiceSchema = z.object({
  host: z.string(),
  ports: z.record(z.number())
})

type Service = z.infer<typeof ServiceSchema>

// All services in the Landale system
// Using Tailscale hostnames for consistency
export const SERVICE_CONFIG: Record<string, Service> = {
  // Mac Mini (saya) services
  server: {
    host: process.env.SERVER_HOST || 'saya',
    ports: {
      http: 7175,
      ws: 7175,
      tcp: 8080
    }
  },
  database: {
    host: process.env.DATABASE_HOST || 'saya',
    ports: {
      postgres: 5432
    }
  },
  
  // Mac Studio (zelan) services
  phononmaser: {
    host: process.env.PHONONMASER_HOST || 'zelan',
    ports: {
      ws: 8889,
      health: 8890
    }
  },
  lmStudio: {
    host: process.env.LM_STUDIO_HOST || 'zelan',
    ports: {
      api: 1234
    }
  },
  
  // Unraid services
  storage: {
    host: process.env.STORAGE_HOST || 'unraid',
    ports: {
      smb: 445,
      http: 80
    }
  }
}

export class ServiceRegistry {
  constructor(private config = SERVICE_CONFIG) {}
  
  getUrl(service: string, port?: string): string {
    const serviceConfig = this.config[service]
    if (!serviceConfig) {
      throw new Error(`Unknown service: ${service}`)
    }
    
    const portName = port || 'http' || Object.keys(serviceConfig.ports)[0]
    const portNumber = serviceConfig.ports[portName]
    
    if (!portNumber) {
      throw new Error(`Unknown port ${portName} for service ${service}`)
    }
    
    return `http://${serviceConfig.host}:${portNumber}`
  }
  
  getWebSocketUrl(service: string, port = 'ws'): string {
    const url = this.getUrl(service, port)
    return url.replace('http://', 'ws://')
  }
  
  getTcpEndpoint(service: string, port = 'tcp'): { host: string; port: number } {
    const serviceConfig = this.config[service]
    if (!serviceConfig) {
      throw new Error(`Unknown service: ${service}`)
    }
    
    return {
      host: serviceConfig.host,
      port: serviceConfig.ports[port] || serviceConfig.ports.tcp
    }
  }
  
  async healthCheck(service: string): Promise<boolean> {
    try {
      const healthPort = this.config[service]?.ports.health || this.config[service]?.ports.http
      if (!healthPort) return false
      
      const url = `http://${this.config[service].host}:${healthPort}/health`
      const response = await fetch(url, { 
        signal: AbortSignal.timeout(5000) 
      })
      
      return response.ok
    } catch {
      return false
    }
  }
  
  async checkAll(): Promise<Record<string, boolean>> {
    const results: Record<string, boolean> = {}
    
    for (const service of Object.keys(this.config)) {
      results[service] = await this.healthCheck(service)
    }
    
    return results
  }
}

// Export singleton instance
export const services = new ServiceRegistry()

// Export for special cases
export function getDatabaseUrl(
  database = 'landale',
  user = process.env.DB_USER || 'landale', 
  password = process.env.DB_PASSWORD || 'landale'
): string {
  const { host, port } = services.getTcpEndpoint('database', 'postgres')
  return `postgresql://${user}:${password}@${host}:${port}/${database}`
}