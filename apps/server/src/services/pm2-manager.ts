import pm2 from 'pm2'
import { createLogger } from '@landale/logger'
import { SERVICE_CONFIG } from '@landale/service-config'

const log = createLogger({ service: 'pm2-manager' })

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
   * For remote machines, this requires PM2 to be configured with RPC
   */
  async connect(machine: string): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.connections.get(machine)) {
        resolve()
        return
      }

      // For local machine
      if (machine === 'localhost' || machine === SERVICE_CONFIG.server.host) {
        pm2.connect((err) => {
          if (err) {
            log.error('Failed to connect to local PM2', { error: { message: err.message } })
            reject(err)
            return
          }
          this.connections.set(machine, true)
          log.info('Connected to local PM2')
          resolve()
        })
      } else {
        // For remote machines, we'll use HTTP API
        // This requires pm2-web or custom PM2 HTTP API on each machine
        log.warn('Remote PM2 connections not yet implemented', { metadata: { machine } })
        reject(new Error('Remote PM2 connections not yet implemented'))
      }
    })
  }

  /**
   * List all processes managed by PM2
   */
  async list(machine: string): Promise<ProcessInfo[]> {
    await this.connect(machine)

    return new Promise((resolve, reject) => {
      pm2.list((err, processDescriptionList) => {
        if (err) {
          log.error('Failed to list PM2 processes', { error: { message: err.message } })
          reject(err)
          return
        }

        const processes: ProcessInfo[] = processDescriptionList.map((proc) => ({
          name: proc.name || 'unknown',
          pm_id: proc.pm_id || 0,
          status: proc.pm2_env?.status || 'stopped',
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

  /**
   * Start a process
   */
  async start(machine: string, processName: string): Promise<void> {
    await this.connect(machine)

    return new Promise((resolve, reject) => {
      pm2.start(processName, (err) => {
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

  /**
   * Stop a process
   */
  async stop(machine: string, processName: string): Promise<void> {
    await this.connect(machine)

    return new Promise((resolve, reject) => {
      pm2.stop(processName, (err) => {
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

  /**
   * Restart a process
   */
  async restart(machine: string, processName: string): Promise<void> {
    await this.connect(machine)

    return new Promise((resolve, reject) => {
      pm2.restart(processName, (err) => {
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

  /**
   * Get detailed information about a process
   */
  async describe(machine: string, processName: string): Promise<any> {
    await this.connect(machine)

    return new Promise((resolve, reject) => {
      pm2.describe(processName, (err, processDescription) => {
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

  /**
   * Flush logs for a process
   */
  async flush(machine: string, processName?: string): Promise<void> {
    await this.connect(machine)

    return new Promise((resolve, reject) => {
      pm2.flush(processName, (err) => {
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
      })
    })
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