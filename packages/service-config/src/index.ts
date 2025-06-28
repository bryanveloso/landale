/**
 * Service configuration management
 * Reads from services.json with environment variable overrides
 */
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

// Service configuration type
export type Service = {
  host: string
  ports: Record<string, number>
}

// Known service names
export type ServiceName = 
  | 'server'
  | 'database'
  | 'seq'
  | 'phononmaser'
  | 'analysis'
  | 'lms'
  | 'obs'
  | 'dashboard'
  | 'overlays'
  | 'storage'

type ServicesConfig = {
  services: Record<ServiceName, Service>
}

// Load the configuration file
function loadConfig(): Record<ServiceName, Service> {
  const configPath = join(__dirname, '..', 'services.json')
  const configData = readFileSync(configPath, 'utf-8')
  const config = JSON.parse(configData) as ServicesConfig

  // Apply environment variable overrides
  const services = { ...config.services }

  // Override hosts if environment variables are set
  if (process.env.SERVER_HOST) services.server.host = process.env.SERVER_HOST
  if (process.env.DATABASE_HOST) services.database.host = process.env.DATABASE_HOST
  if (process.env.SEQ_HOST) services.seq.host = process.env.SEQ_HOST
  if (process.env.PHONONMASER_HOST) services.phononmaser.host = process.env.PHONONMASER_HOST
  if (process.env.ANALYSIS_HOST) services.analysis.host = process.env.ANALYSIS_HOST
  if (process.env.LMS_HOST) services.lms.host = process.env.LMS_HOST
  if (process.env.OBS_HOST) services.obs.host = process.env.OBS_HOST
  if (process.env.DASHBOARD_HOST) services.dashboard.host = process.env.DASHBOARD_HOST
  if (process.env.OVERLAYS_HOST) services.overlays.host = process.env.OVERLAYS_HOST
  if (process.env.STORAGE_HOST) services.storage.host = process.env.STORAGE_HOST

  // Override specific ports if needed
  if (process.env.SEQ_PORT) services.seq.ports.http = parseInt(process.env.SEQ_PORT, 10)

  return services
}

// Export the configuration
export const SERVICE_CONFIG = loadConfig()

/**
 * Service registry for URL generation
 */
export class ServiceRegistry {
  getUrl(service: ServiceName, port?: string): string {
    const serviceConfig = SERVICE_CONFIG[service]
    const portName = port || 'http'
    const portNumber = serviceConfig.ports[portName]

    if (!portNumber) {
      throw new Error(`Unknown port ${portName} for service ${service}`)
    }

    return `http://${serviceConfig.host}:${portNumber.toString()}`
  }

  getWebSocketUrl(service: ServiceName, port = 'ws'): string {
    const url = this.getUrl(service, port)
    return url.replace('http://', 'ws://')
  }

  getTcpEndpoint(service: ServiceName, port = 'tcp'): { host: string; port: number } {
    const serviceConfig = SERVICE_CONFIG[service]
    const portNumber = serviceConfig.ports[port] ?? serviceConfig.ports.tcp

    if (!portNumber) {
      throw new Error(`No TCP port found for service ${service}`)
    }

    return {
      host: serviceConfig.host,
      port: portNumber
    }
  }
}

// Export singleton instance
export const services = new ServiceRegistry()

// Convenience functions
export function getDatabaseUrl(
  database = 'landale',
  user = process.env.DB_USER || 'landale',
  password = process.env.DB_PASSWORD || 'landale'
): string {
  const { host, port } = services.getTcpEndpoint('database', 'postgres')
  return `postgresql://${user}:${password}@${host}:${port.toString()}/${database}`
}

export function getSeqUrl(): string {
  return services.getUrl('seq', 'http')
}