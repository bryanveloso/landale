import pm2 from 'pm2'
import { createLogger } from '@landale/logger'
import { SERVICE_CONFIG } from '@landale/service-config'

const log = createLogger({ service: 'pm2' })

// Machine registry with connection details
interface MachineConfig {
  host: string
  port: number
  token: string
}

const MACHINE_REGISTRY: Record<string, MachineConfig> = {
  saya: {
    host: 'saya.local',
    port: 9615,
    token: process.env.PM2_AGENT_TOKEN || 'change-me-in-production'
  },
  zelan: {
    host: 'zelan.local',
    port: 9615,
    token: process.env.PM2_AGENT_TOKEN || 'change-me-in-production'
  },
  demi: {
    host: 'demi.local',
    port: 9615,
    token: process.env.PM2_AGENT_TOKEN || 'change-me-in-production'
  },
  alys: {
    host: 'alys.local',
    port: 9615,
    token: process.env.PM2_AGENT_TOKEN || 'change-me-in-production'
  }
}

export interface ProcessInfo {
  name: string
  pm_id: number
  status: 'online' | 'stopping' | 'stopped' | 'launching' | 'errored'
  cpu: number
  memory: number
  uptime: number
  restart_time: number
  unstable_restarts: number
}

export interface PM2Action {
  machine: string
  process: string
  action: 'start' | 'stop' | 'restart' | 'delete'
}

class PM2Manager {
  private connections: Map<string, boolean> = new Map()

  /**
   * Connect to PM2 on a specific machine
   * For remote machines, this uses the PM2 HTTP Agent
   */
  async connect(machine: string): Promise<void> {
    if (this.connections.get(machine)) {
      return
    }

    // For local machine
    if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
      return new Promise((resolve, reject) => {
        pm2.connect((err: Error | null) => {
          if (err) {
            log.error('Failed to connect to local PM2', { error: { message: err.message } })
            reject(err)
            return
          }
          this.connections.set(machine, true)
          log.info('Connected to local PM2')
          resolve()
        })
      })
    } else {
      // For remote machines, test the HTTP connection
      const config = MACHINE_REGISTRY[machine]
      if (!config) {
        throw new Error(`Unknown machine: ${machine}`)
      }
      
      try {
        const response = await fetch(`http://${config.host}:${config.port}/health`, {
          headers: {
            'Authorization': `Bearer ${config.token}`
          }
        })
        
        if (!response.ok) {
          throw new Error(`Failed to connect to ${machine}: ${response.status}`)
        }
        
        this.connections.set(machine, true)
        log.info(`Connected to remote PM2 on ${machine}`)
      } catch (error) {
        log.error(`Failed to connect to remote PM2 on ${machine}`, { 
          error: error instanceof Error ? { message: error.message } : { message: String(error) }
        })
        throw error
      }
    }
  }

  /**
   * List all processes managed by PM2
   */
  async list(machine: string): Promise<ProcessInfo[]> {
    await this.connect(machine)

    // Local PM2
    if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
      return new Promise((resolve, reject) => {
        pm2.list((err: Error | null, processDescriptionList) => {
          if (err) {
            log.error('Failed to list PM2 processes', { error: { message: err.message } })
            reject(err)
            return
          }

          const processes: ProcessInfo[] = processDescriptionList.map((proc) => ({
            name: proc.name || 'unknown',
            pm_id: proc.pm_id || 0,
            status: (proc.pm2_env?.status || 'stopped') as ProcessInfo['status'],
            cpu: proc.monit?.cpu || 0,
            memory: proc.monit?.memory || 0,
            uptime: proc.pm2_env?.pm_uptime || 0,
            restart_time: proc.pm2_env?.restart_time || 0,
            unstable_restarts: proc.pm2_env?.unstable_restarts || 0
          }))

          resolve(processes)
        })
      })
    }
    
    // Remote PM2 via HTTP
    const config = MACHINE_REGISTRY[machine]
    if (!config) {
      throw new Error(`Unknown machine: ${machine}`)
    }
    const response = await fetch(`http://${config.host}:${config.port}/processes`, {
      headers: {
        'Authorization': `Bearer ${config.token}`
      }
    })
    
    if (!response.ok) {
      throw new Error(`Failed to list processes on ${machine}: ${response.status}`)
    }
    
    return response.json() as Promise<ProcessInfo[]>
  }

  /**
   * Start a process
   */
  async start(machine: string, processName: string): Promise<void> {
    await this.connect(machine)

    // Local PM2
    if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
      return new Promise((resolve, reject) => {
        pm2.start(processName, (err: Error | null) => {
          if (err) {
            log.error('Failed to start process', { 
              error: { message: err.message },
              metadata: { machine, processName }
            })
            reject(err)
            return
          }
          log.info('Process started', { metadata: { machine, processName } })
          resolve()
        })
      })
    }
    
    // Remote PM2 via HTTP
    const config = MACHINE_REGISTRY[machine]
    if (!config) {
      throw new Error(`Unknown machine: ${machine}`)
    }
    const response = await fetch(`http://${config.host}:${config.port}/process/${encodeURIComponent(processName)}/start`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.token}`
      }
    })
    
    if (!response.ok) {
      const error = await response.json() as { error?: string }
      throw new Error(error.error || `Failed to start process on ${machine}`)
    }
    
    log.info('Process started', { metadata: { machine, processName } })
  }

  /**
   * Stop a process
   */
  async stop(machine: string, processName: string): Promise<void> {
    await this.connect(machine)

    // Local PM2
    if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
      return new Promise((resolve, reject) => {
        pm2.stop(processName, (err: Error | null) => {
          if (err) {
            log.error('Failed to stop process', { 
              error: { message: err.message },
              metadata: { machine, processName }
            })
            reject(err)
            return
          }
          log.info('Process stopped', { metadata: { machine, processName } })
          resolve()
        })
      })
    }
    
    // Remote PM2 via HTTP
    const config = MACHINE_REGISTRY[machine]
    if (!config) {
      throw new Error(`Unknown machine: ${machine}`)
    }
    const response = await fetch(`http://${config.host}:${config.port}/process/${encodeURIComponent(processName)}/stop`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.token}`
      }
    })
    
    if (!response.ok) {
      const error = await response.json() as { error?: string }
      throw new Error(error.error || `Failed to stop process on ${machine}`)
    }
    
    log.info('Process stopped', { metadata: { machine, processName } })
  }

  /**
   * Restart a process
   */
  async restart(machine: string, processName: string): Promise<void> {
    await this.connect(machine)

    // Local PM2
    if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
      return new Promise((resolve, reject) => {
        pm2.restart(processName, (err: Error | null) => {
          if (err) {
            log.error('Failed to restart process', { 
              error: { message: err.message },
              metadata: { machine, processName }
            })
            reject(err)
            return
          }
          log.info('Process restarted', { metadata: { machine, processName } })
          resolve()
        })
      })
    }
    
    // Remote PM2 via HTTP
    const config = MACHINE_REGISTRY[machine]
    if (!config) {
      throw new Error(`Unknown machine: ${machine}`)
    }
    const response = await fetch(`http://${config.host}:${config.port}/process/${encodeURIComponent(processName)}/restart`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.token}`
      }
    })
    
    if (!response.ok) {
      const error = await response.json() as { error?: string }
      throw new Error(error.error || `Failed to restart process on ${machine}`)
    }
    
    log.info('Process restarted', { metadata: { machine, processName } })
  }

  /**
   * Get detailed information about a process
   */
  async describe(machine: string, processName: string): Promise<pm2.ProcessDescription[]> {
    await this.connect(machine)

    // Local PM2
    if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
      return new Promise((resolve, reject) => {
        pm2.describe(processName, (err: Error | null, processDescription) => {
          if (err) {
            log.error('Failed to describe process', { 
              error: { message: err.message },
              metadata: { machine, processName }
            })
            reject(err)
            return
          }
          resolve(processDescription)
        })
      })
    }
    
    // Remote PM2 via HTTP
    const config = MACHINE_REGISTRY[machine]
    if (!config) {
      throw new Error(`Unknown machine: ${machine}`)
    }
    const response = await fetch(`http://${config.host}:${config.port}/process/${encodeURIComponent(processName)}/describe`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.token}`
      }
    })
    
    if (!response.ok) {
      const error = await response.json() as { error?: string }
      throw new Error(error.error || `Failed to describe process on ${machine}`)
    }
    
    return response.json() as Promise<pm2.ProcessDescription[]>
  }

  /**
   * Flush logs for a process
   */
  async flush(machine: string, processName?: string): Promise<void> {
    await this.connect(machine)

    // Local PM2
    if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
      return new Promise((resolve, reject) => {
        const callback = (err: Error | null) => {
          if (err) {
            log.error('Failed to flush logs', { 
              error: { message: err.message },
              metadata: { machine, processName }
            })
            reject(err)
            return
          }
          log.info('Logs flushed', { metadata: { machine, processName } })
          resolve()
        }
        
        if (processName) {
          pm2.flush(processName, callback)
        } else {
          // Flush all processes
          pm2.list((err: Error | null, processes) => {
            if (err) {
              callback(err)
              return
            }
            
            // Flush logs for all processes
            let flushCount = 0
            const totalProcesses = processes.length
            
            if (totalProcesses === 0) {
              callback(null)
              return
            }
            
            processes.forEach((proc) => {
              pm2.flush(proc.pm_id || 0, (flushErr: Error | null) => {
                flushCount++
                if (flushErr) {
                  callback(flushErr)
                  return
                }
                if (flushCount === totalProcesses) {
                  callback(null)
                }
              })
            })
          })
        }
      })
    }
    
    // Remote PM2 via HTTP
    const config = MACHINE_REGISTRY[machine]
    if (!config) {
      throw new Error(`Unknown machine: ${machine}`)
    }
    const url = processName 
      ? `http://${config.host}:${config.port}/flush?process=${encodeURIComponent(processName)}`
      : `http://${config.host}:${config.port}/flush`
      
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.token}`
      }
    })
    
    if (!response.ok) {
      const error = await response.json() as { error?: string }
      throw new Error(error.error || `Failed to flush logs on ${machine}`)
    }
    
    log.info('Logs flushed', { metadata: { machine, processName } })
  }

  /**
   * Disconnect from PM2
   */
  disconnect(): void {
    pm2.disconnect()
    this.connections.clear()
    log.info('Disconnected from PM2')
  }
}

// Export singleton instance
export const pm2Manager = new PM2Manager()

// Cleanup on exit
process.on('SIGINT', () => {
  pm2Manager.disconnect()
})

process.on('SIGTERM', () => {
  pm2Manager.disconnect()
})