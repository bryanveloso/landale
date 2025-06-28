import { logger } from '@landale/logger'
import type { AgentConfig, AgentStatus, AgentCommand, AgentResponse, AgentCapability } from './types'

export abstract class BaseAgent {
  protected config: AgentConfig
  protected ws: WebSocket | null = null
  protected reconnectTimer: Timer | null = null
  protected heartbeatTimer: Timer | null = null
  protected status: AgentStatus
  protected log = logger.child({ component: 'agent' })

  constructor(config: AgentConfig) {
    this.config = config
    this.status = {
      id: config.id,
      name: config.name,
      host: config.host,
      status: 'offline',
      lastSeen: new Date(),
      capabilities: this.getCapabilities()
    }
  }

  abstract getCapabilities(): AgentCapability[]
  abstract handleCommand(command: AgentCommand): Promise<AgentResponse>

  async start() {
    this.log.info(`Starting agent ${this.config.name} on ${this.config.host}`)
    await this.connect()
  }

  async stop() {
    this.log.info(`Stopping agent ${this.config.name}`)
    
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer)
      this.heartbeatTimer = null
    }
    
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
  }

  protected async connect() {
    try {
      const wsUrl = this.config.serverUrl.replace('http', 'ws')
      this.ws = new WebSocket(`${wsUrl}/agent`)
      
      this.ws.addEventListener('open', () => {
        this.log.info('Connected to server')
        this.status.status = 'online'
        this.sendStatus()
        this.startHeartbeat()
      })

      this.ws.addEventListener('message', async (event) => {
        try {
          const command = JSON.parse(event.data) as AgentCommand
          this.log.debug('Received command', command)
          
          const response = await this.handleCommand(command)
          this.sendResponse(response)
        } catch (error) {
          this.log.error('Error handling message', error)
        }
      })

      this.ws.addEventListener('close', () => {
        this.log.warn('Disconnected from server')
        this.status.status = 'offline'
        this.scheduleReconnect()
      })

      this.ws.addEventListener('error', (error) => {
        this.log.error('WebSocket error', error)
        this.status.status = 'error'
      })
    } catch (error) {
      this.log.error('Failed to connect', error)
      this.scheduleReconnect()
    }
  }

  protected scheduleReconnect() {
    if (this.reconnectTimer) return
    
    const interval = this.config.reconnectInterval || 5000
    this.log.info(`Reconnecting in ${interval}ms`)
    
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      this.connect()
    }, interval)
  }

  protected startHeartbeat() {
    if (this.heartbeatTimer) return
    
    const interval = this.config.heartbeatInterval || 30000
    this.heartbeatTimer = setInterval(() => {
      this.sendStatus()
    }, interval)
  }

  protected sendStatus() {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return
    
    this.status.lastSeen = new Date()
    this.ws.send(JSON.stringify({
      type: 'status',
      data: this.status
    }))
  }

  protected sendResponse(response: AgentResponse) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return
    
    this.ws.send(JSON.stringify({
      type: 'response',
      data: response
    }))
  }

  protected updateMetrics(metrics: Record<string, unknown>) {
    this.status.metrics = metrics
  }
}