import { $ } from 'bun'
import { BaseAgent } from './base-agent'
import type { AgentCapability, AgentCommand, AgentResponse, ProcessInfo, ServiceHealth } from './types'

interface ServiceConfig {
  name: string
  type: 'docker' | 'process' | 'launchd'
  dockerService?: string
  processName?: string
  launchdLabel?: string
  healthCheck?: () => Promise<boolean>
}

export class MacOSAgent extends BaseAgent {
  private services: Map<string, ServiceConfig> = new Map()
  private monitoringTimer: Timer | null = null

  getCapabilities(): AgentCapability[] {
    return [
      {
        name: 'process',
        description: 'Process management',
        actions: ['list', 'start', 'stop', 'restart', 'status']
      },
      {
        name: 'service',
        description: 'Service management',
        actions: ['list', 'start', 'stop', 'restart', 'health']
      },
      {
        name: 'system',
        description: 'System information',
        actions: ['info', 'metrics']
      }
    ]
  }

  registerService(config: ServiceConfig) {
    this.services.set(config.name, config)
  }

  async start() {
    await super.start()
    this.startMonitoring()
  }

  async stop() {
    if (this.monitoringTimer) {
      clearInterval(this.monitoringTimer)
      this.monitoringTimer = null
    }
    await super.stop()
  }

  private startMonitoring() {
    if (this.monitoringTimer) return
    
    // Monitor every 30 seconds
    this.monitoringTimer = setInterval(async () => {
      const metrics = await this.getSystemMetrics()
      this.updateMetrics(metrics)
      this.sendStatus()
    }, 30000)
  }

  async handleCommand(command: AgentCommand): Promise<AgentResponse> {
    try {
      const [capability, action] = command.action.split('.')
      
      switch (capability) {
        case 'process':
          return await this.handleProcessCommand(action, command)
        case 'service':
          return await this.handleServiceCommand(action, command)
        case 'system':
          return await this.handleSystemCommand(action, command)
        default:
          throw new Error(`Unknown capability: ${capability}`)
      }
    } catch (error) {
      return {
        commandId: command.id,
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
        timestamp: new Date()
      }
    }
  }

  private async handleProcessCommand(action: string, command: AgentCommand): Promise<AgentResponse> {
    switch (action) {
      case 'list':
        const processes = await this.listProcesses()
        return {
          commandId: command.id,
          success: true,
          result: processes,
          timestamp: new Date()
        }
      
      case 'status':
        const processName = command.params?.name as string
        if (!processName) throw new Error('Process name required')
        
        const status = await this.getProcessStatus(processName)
        return {
          commandId: command.id,
          success: true,
          result: status,
          timestamp: new Date()
        }
      
      default:
        throw new Error(`Unknown process action: ${action}`)
    }
  }

  private async handleServiceCommand(action: string, command: AgentCommand): Promise<AgentResponse> {
    const serviceName = command.params?.name as string
    const service = this.services.get(serviceName)
    
    if (!service && action !== 'list') {
      throw new Error(`Unknown service: ${serviceName}`)
    }

    switch (action) {
      case 'list':
        return {
          commandId: command.id,
          success: true,
          result: Array.from(this.services.keys()),
          timestamp: new Date()
        }
      
      case 'start':
        await this.startService(service!)
        return {
          commandId: command.id,
          success: true,
          timestamp: new Date()
        }
      
      case 'stop':
        await this.stopService(service!)
        return {
          commandId: command.id,
          success: true,
          timestamp: new Date()
        }
      
      case 'restart':
        await this.restartService(service!)
        return {
          commandId: command.id,
          success: true,
          timestamp: new Date()
        }
      
      case 'health':
        const health = await this.checkServiceHealth(service!)
        return {
          commandId: command.id,
          success: true,
          result: health,
          timestamp: new Date()
        }
      
      default:
        throw new Error(`Unknown service action: ${action}`)
    }
  }

  private async handleSystemCommand(action: string, command: AgentCommand): Promise<AgentResponse> {
    switch (action) {
      case 'info':
        const info = await this.getSystemInfo()
        return {
          commandId: command.id,
          success: true,
          result: info,
          timestamp: new Date()
        }
      
      case 'metrics':
        const metrics = await this.getSystemMetrics()
        return {
          commandId: command.id,
          success: true,
          result: metrics,
          timestamp: new Date()
        }
      
      default:
        throw new Error(`Unknown system action: ${action}`)
    }
  }

  private async listProcesses(): Promise<ProcessInfo[]> {
    const result = await $`ps aux | grep -E "(bun|node|python)" | grep -v grep`.text()
    const lines = result.trim().split('\n').filter(Boolean)
    
    return lines.map(line => {
      const parts = line.split(/\s+/)
      return {
        name: parts.slice(10).join(' '),
        pid: parseInt(parts[1]),
        status: 'running' as const,
        cpu: parseFloat(parts[2]),
        memory: parseFloat(parts[3])
      }
    })
  }

  private async getProcessStatus(name: string): Promise<ProcessInfo> {
    try {
      const result = await $`pgrep -f ${name}`.text()
      const pid = parseInt(result.trim())
      
      if (pid) {
        const info = await $`ps -p ${pid} -o %cpu,%mem,etime`.text()
        const [header, data] = info.trim().split('\n')
        const [cpu, mem, uptime] = data.trim().split(/\s+/)
        
        return {
          name,
          pid,
          status: 'running',
          cpu: parseFloat(cpu),
          memory: parseFloat(mem)
        }
      }
    } catch {
      // Process not found
    }
    
    return {
      name,
      status: 'stopped'
    }
  }

  private async startService(service: ServiceConfig) {
    switch (service.type) {
      case 'docker':
        await $`docker compose up -d ${service.dockerService}`
        break
      
      case 'launchd':
        await $`launchctl load ${service.launchdLabel}`
        break
      
      case 'process':
        // This would need custom logic per service
        throw new Error('Process start not implemented')
    }
  }

  private async stopService(service: ServiceConfig) {
    switch (service.type) {
      case 'docker':
        await $`docker compose stop ${service.dockerService}`
        break
      
      case 'launchd':
        await $`launchctl unload ${service.launchdLabel}`
        break
      
      case 'process':
        if (service.processName) {
          await $`pkill -f ${service.processName}`
        }
        break
    }
  }

  private async restartService(service: ServiceConfig) {
    await this.stopService(service)
    await new Promise(resolve => setTimeout(resolve, 2000))
    await this.startService(service)
  }

  private async checkServiceHealth(service: ServiceConfig): Promise<ServiceHealth> {
    try {
      if (service.healthCheck) {
        const healthy = await service.healthCheck()
        return {
          name: service.name,
          status: healthy ? 'healthy' : 'unhealthy',
          lastCheck: new Date()
        }
      }

      // Default health check based on process
      const status = await this.getProcessStatus(service.processName || service.name)
      return {
        name: service.name,
        status: status.status === 'running' ? 'healthy' : 'unhealthy',
        lastCheck: new Date()
      }
    } catch (error) {
      return {
        name: service.name,
        status: 'unknown',
        message: error instanceof Error ? error.message : 'Health check failed',
        lastCheck: new Date()
      }
    }
  }

  private async getSystemInfo() {
    const hostname = await $`hostname`.text()
    const os = await $`sw_vers -productVersion`.text()
    const uptime = await $`uptime`.text()
    
    return {
      hostname: hostname.trim(),
      os: `macOS ${os.trim()}`,
      uptime: uptime.trim()
    }
  }

  private async getSystemMetrics() {
    // CPU usage
    const cpu = await $`top -l 1 -n 0 | grep "CPU usage"`.text()
    const cpuMatch = cpu.match(/(\d+\.\d+)% user/)
    const cpuUsage = cpuMatch ? parseFloat(cpuMatch[1]) : 0

    // Memory usage
    const memory = await $`vm_stat | grep -E "(free|active|inactive|wired)"`.text()
    const pageSize = 4096 // macOS page size
    const memStats = memory.split('\n').reduce((acc, line) => {
      const match = line.match(/(.+):\s+(\d+)/)
      if (match) {
        acc[match[1].trim()] = parseInt(match[2]) * pageSize
      }
      return acc
    }, {} as Record<string, number>)

    const totalMemory = Object.values(memStats).reduce((a, b) => a + b, 0)
    const freeMemory = memStats['Pages free'] || 0
    const usedMemory = totalMemory - freeMemory

    return {
      cpu: {
        usage: cpuUsage
      },
      memory: {
        total: totalMemory,
        used: usedMemory,
        free: freeMemory,
        percentage: (usedMemory / totalMemory) * 100
      }
    }
  }
}