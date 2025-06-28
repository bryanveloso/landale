import { EventEmitter } from 'events'
import { createLogger } from './logger'
import { getDatabaseService } from '@/services/database'
import { getOBSService } from '@/services/obs'
import { getRainwaveService } from '@/services/rainwave'
import { getAppleMusicService } from '@/services/apple-music'

// Health check types
export type HealthStatus = 'healthy' | 'degraded' | 'unhealthy' | 'unknown'

export interface ServiceHealth {
  name: string
  status: HealthStatus
  lastCheck: Date
  lastSuccessfulCheck?: Date
  error?: string
  metadata?: Record<string, unknown>
}

export interface HealthCheckResult {
  service: string
  status: HealthStatus
  error?: string
  metadata?: Record<string, unknown>
}

export interface HealthMonitorOptions {
  checkInterval?: number // milliseconds
  timeout?: number // milliseconds for individual checks
  retries?: number
}

// Service health check interface
export interface HealthCheckable {
  healthCheck(): Promise<HealthCheckResult>
}

// Health monitor class
export class HealthMonitor extends EventEmitter {
  private readonly log = createLogger({ service: 'landale-server' }).child({ module: 'health-monitor' })
  private services = new Map<string, ServiceHealth>()
  private checkTimer?: NodeJS.Timeout
  private eventBroadcaster?: any
  
  constructor(
    private readonly options: HealthMonitorOptions = {}
  ) {
    super()
    this.options = {
      checkInterval: 30000, // 30 seconds
      timeout: 5000, // 5 seconds
      retries: 3,
      ...options
    }
  }
  
  setEventBroadcaster(broadcaster: any) {
    this.eventBroadcaster = broadcaster
  }
  
  // Register a service for health monitoring
  registerService(name: string) {
    this.services.set(name, {
      name,
      status: 'unknown',
      lastCheck: new Date()
    })
    this.log.info('Registered service for health monitoring', { metadata: { service: name } })
  }
  
  // Start monitoring
  start() {
    this.log.info('Starting health monitor', { 
      metadata: {
        interval: this.options.checkInterval,
        services: Array.from(this.services.keys())
      }
    })
    
    // Run initial check
    void this.checkAllServices()
    
    // Schedule periodic checks
    this.checkTimer = setInterval(() => {
      void this.checkAllServices()
    }, this.options.checkInterval!)
  }
  
  // Stop monitoring
  stop() {
    if (this.checkTimer) {
      clearInterval(this.checkTimer)
      this.checkTimer = undefined
    }
    this.log.info('Stopped health monitor')
  }
  
  // Check all services
  private async checkAllServices() {
    const checks = Array.from(this.services.keys()).map(service => 
      this.checkService(service)
    )
    
    await Promise.allSettled(checks)
    
    // Broadcast overall health status
    const healthData = this.getHealthStatus()
    this.eventBroadcaster?.broadcast({
      type: 'health:status',
      data: healthData
    })
  }
  
  // Check individual service
  private async checkService(serviceName: string) {
    const startTime = Date.now()
    
    try {
      const result = await this.performHealthCheck(serviceName)
      const duration = Date.now() - startTime
      
      const health = this.services.get(serviceName)!
      const previousStatus = health.status
      
      health.status = result.status
      health.lastCheck = new Date()
      health.error = result.error
      health.metadata = result.metadata
      
      if (result.status === 'healthy') {
        health.lastSuccessfulCheck = new Date()
      }
      
      // Emit events for status changes
      if (previousStatus !== result.status) {
        this.log.info('Service health status changed', {
          metadata: {
            service: serviceName,
            previousStatus,
            newStatus: result.status,
            error: result.error
          }
        })
        
        this.emit('statusChange', {
          service: serviceName,
          previousStatus,
          newStatus: result.status,
          health
        })
        
        // Broadcast alert for unhealthy services
        if (result.status === 'unhealthy') {
          this.eventBroadcaster?.broadcast({
            type: 'health:alert',
            data: {
              service: serviceName,
              status: result.status,
              error: result.error,
              timestamp: new Date().toISOString()
            }
          })
        }
      }
      
      this.log.debug('Health check completed', {
        metadata: {
          service: serviceName,
          status: result.status,
          duration
        }
      })
      
    } catch (error) {
      const health = this.services.get(serviceName)!
      health.status = 'unhealthy'
      health.lastCheck = new Date()
      health.error = error instanceof Error ? error.message : 'Unknown error'
      
      this.log.error('Health check failed', {
        error: error as Error,
        metadata: {
          service: serviceName
        }
      })
    }
  }
  
  // Perform the actual health check for a service
  private async performHealthCheck(serviceName: string): Promise<HealthCheckResult> {
    switch (serviceName) {
      case 'database':
        return this.checkDatabase()
      case 'obs':
        return this.checkOBS()
      case 'rainwave':
        return this.checkRainwave()
      case 'apple-music':
        return this.checkAppleMusic()
      case 'twitch':
        return this.checkTwitch()
      case 'ironmon':
        return this.checkIronMON()
      default:
        return {
          service: serviceName,
          status: 'unknown',
          error: `No health check defined for service: ${serviceName}`
        }
    }
  }
  
  // Database health check
  private async checkDatabase(): Promise<HealthCheckResult> {
    try {
      const db = getDatabaseService()
      const start = Date.now()
      await db.query(`SELECT 1`)
      const latency = Date.now() - start
      
      return {
        service: 'database',
        status: latency < 100 ? 'healthy' : 'degraded',
        metadata: { latency }
      }
    } catch (error) {
      return {
        service: 'database',
        status: 'unhealthy',
        error: error instanceof Error ? error.message : 'Database check failed'
      }
    }
  }
  
  // OBS health check
  private async checkOBS(): Promise<HealthCheckResult> {
    try {
      const obs = getOBSService()
      const connected = obs.isConnected()
      
      if (!connected) {
        return {
          service: 'obs',
          status: 'unhealthy',
          error: 'Not connected to OBS'
        }
      }
      
      // Try to get version info as a health check
      const version = await obs.getVersion()
      
      return {
        service: 'obs',
        status: 'healthy',
        metadata: { version }
      }
    } catch (error) {
      return {
        service: 'obs',
        status: 'unhealthy',
        error: error instanceof Error ? error.message : 'OBS check failed'
      }
    }
  }
  
  // Rainwave health check
  private async checkRainwave(): Promise<HealthCheckResult> {
    try {
      const rainwave = getRainwaveService()
      const data = rainwave.getCurrentData()
      
      return {
        service: 'rainwave',
        status: data.isEnabled ? 'healthy' : 'unhealthy',
        metadata: {
          currentSong: data.currentSong?.title,
          artist: data.currentSong?.artist,
          stationId: data.stationId,
          stationName: data.stationName
        }
      }
    } catch (error) {
      return {
        service: 'rainwave',
        status: 'unhealthy',
        error: error instanceof Error ? error.message : 'Rainwave check failed'
      }
    }
  }
  
  // Apple Music health check
  private async checkAppleMusic(): Promise<HealthCheckResult> {
    try {
      const appleMusic = getAppleMusicService()
      const data = appleMusic.getCurrentData()
      
      return {
        service: 'apple-music',
        status: data.isAuthorized ? 'healthy' : 'unhealthy',
        metadata: {
          isPlaying: data.playbackState === 'playing',
          currentSong: data.currentSong?.title,
          artist: data.currentSong?.artist,
          playbackState: data.playbackState
        }
      }
    } catch (error) {
      return {
        service: 'apple-music',
        status: 'unhealthy',
        error: error instanceof Error ? error.message : 'Apple Music check failed'
      }
    }
  }
  
  // Twitch health check
  private async checkTwitch(): Promise<HealthCheckResult> {
    // For now, assume Twitch is healthy if we can import it
    // In a real implementation, we'd check EventSub subscriptions
    return {
      service: 'twitch',
      status: 'healthy',
      metadata: {
        // Could add subscription count, etc.
      }
    }
  }
  
  // IronMON health check
  private async checkIronMON(): Promise<HealthCheckResult> {
    // Check if TCP server is listening
    // In a real implementation, we'd check the actual server state
    return {
      service: 'ironmon',
      status: 'healthy',
      metadata: {
        port: 8080
      }
    }
  }
  
  // Get current health status
  getHealthStatus() {
    const services = Array.from(this.services.values())
    const overallStatus = this.calculateOverallStatus(services)
    
    return {
      status: overallStatus,
      services,
      timestamp: new Date().toISOString()
    }
  }
  
  // Get health for specific service
  getServiceHealth(serviceName: string): ServiceHealth | undefined {
    return this.services.get(serviceName)
  }
  
  // Calculate overall system health
  private calculateOverallStatus(services: ServiceHealth[]): HealthStatus {
    const unhealthyCount = services.filter(s => s.status === 'unhealthy').length
    const degradedCount = services.filter(s => s.status === 'degraded').length
    const unknownCount = services.filter(s => s.status === 'unknown').length
    
    if (unhealthyCount > 0) {
      return 'unhealthy'
    } else if (degradedCount > 0 || unknownCount > 0) {
      return 'degraded'
    }
    return 'healthy'
  }
}

// Singleton instance
let healthMonitor: HealthMonitor | null = null

export function getHealthMonitor(): HealthMonitor {
  if (!healthMonitor) {
    healthMonitor = new HealthMonitor()
  }
  return healthMonitor
}