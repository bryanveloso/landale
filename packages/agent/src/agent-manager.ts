import { EventEmitter } from 'events'
import { logger } from '@landale/logger'
import type { AgentStatus, AgentCommand, AgentResponse } from './types'

interface ManagedAgent {
  status: AgentStatus
  ws: WebSocket
  lastSeen: Date
}

export class AgentManager extends EventEmitter {
  private agents = new Map<string, ManagedAgent>()
  private log = logger.child({ component: 'agent-manager' })

  constructor() {
    super()
    this.startHealthCheck()
  }

  handleConnection(ws: WebSocket, request: Request) {
    const agentId = new URL(request.url).searchParams.get('id')
    
    ws.addEventListener('message', (event) => {
      try {
        const message = JSON.parse(event.data)
        
        switch (message.type) {
          case 'status':
            this.handleStatus(ws, message.data)
            break
          
          case 'response':
            this.handleResponse(message.data)
            break
        }
      } catch (error) {
        this.log.error('Error handling agent message', error)
      }
    })

    ws.addEventListener('close', () => {
      const agent = this.findAgentByWebSocket(ws)
      if (agent) {
        this.log.info(`Agent disconnected: ${agent.status.name}`)
        agent.status.status = 'offline'
        this.emit('agentDisconnected', agent.status)
        this.agents.delete(agent.status.id)
      }
    })
  }

  private handleStatus(ws: WebSocket, status: AgentStatus) {
    const existing = this.agents.get(status.id)
    
    if (!existing) {
      this.log.info(`New agent connected: ${status.name} (${status.id})`)
      this.emit('agentConnected', status)
    }
    
    this.agents.set(status.id, {
      status,
      ws,
      lastSeen: new Date()
    })
    
    this.emit('agentStatus', status)
  }

  private handleResponse(response: AgentResponse) {
    this.emit(`response:${response.commandId}`, response)
  }

  private findAgentByWebSocket(ws: WebSocket): ManagedAgent | undefined {
    for (const agent of this.agents.values()) {
      if (agent.ws === ws) {
        return agent
      }
    }
  }

  async sendCommand(agentId: string, action: string, params?: Record<string, unknown>): Promise<AgentResponse> {
    const agent = this.agents.get(agentId)
    if (!agent) {
      throw new Error(`Agent ${agentId} not connected`)
    }

    const command: AgentCommand = {
      id: crypto.randomUUID(),
      action,
      params,
      timestamp: new Date()
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.off(`response:${command.id}`, responseHandler)
        reject(new Error('Command timeout'))
      }, 30000)

      const responseHandler = (response: AgentResponse) => {
        clearTimeout(timeout)
        resolve(response)
      }

      this.once(`response:${command.id}`, responseHandler)
      
      agent.ws.send(JSON.stringify(command))
    })
  }

  getAgents(): AgentStatus[] {
    return Array.from(this.agents.values()).map(agent => agent.status)
  }

  getAgent(id: string): AgentStatus | undefined {
    return this.agents.get(id)?.status
  }

  private startHealthCheck() {
    setInterval(() => {
      const now = Date.now()
      
      for (const [id, agent] of this.agents.entries()) {
        const lastSeenMs = agent.lastSeen.getTime()
        const timeSinceLastSeen = now - lastSeenMs
        
        // Mark as offline if no heartbeat for 60 seconds
        if (timeSinceLastSeen > 60000 && agent.status.status === 'online') {
          this.log.warn(`Agent ${agent.status.name} missed heartbeat`)
          agent.status.status = 'offline'
          this.emit('agentStatus', agent.status)
        }
        
        // Remove if no heartbeat for 5 minutes
        if (timeSinceLastSeen > 300000) {
          this.log.warn(`Removing stale agent ${agent.status.name}`)
          this.agents.delete(id)
          this.emit('agentDisconnected', agent.status)
        }
      }
    }, 10000)
  }
}