import { z } from 'zod'
import { t, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import type { AgentManager, AgentStatus } from '@landale/agent'

// We'll inject the agent manager instance
let agentManagerInstance: AgentManager | null = null

export function setAgentManager(manager: AgentManager) {
  agentManagerInstance = manager
}

function getAgentManager(): AgentManager {
  if (!agentManagerInstance) {
    throw new TRPCError({
      code: 'INTERNAL_SERVER_ERROR',
      message: 'Agent manager not initialized'
    })
  }
  return agentManagerInstance
}

export const agentsRouter = t.router({
  // List all connected agents
  list: publicProcedure.query(async () => {
    const manager = getAgentManager()
    return manager.getAgents()
  }),

  // Get a specific agent
  get: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(async ({ input }) => {
      const manager = getAgentManager()
      const agent = manager.getAgent(input.id)
      
      if (!agent) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: `Agent ${input.id} not found`
        })
      }
      
      return agent
    }),

  // Send command to agent
  command: publicProcedure
    .input(z.object({
      agentId: z.string(),
      action: z.string(),
      params: z.record(z.unknown()).optional()
    }))
    .mutation(async ({ input }) => {
      const manager = getAgentManager()
      
      try {
        const response = await manager.sendCommand(
          input.agentId,
          input.action,
          input.params
        )
        
        if (!response.success) {
          throw new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: response.error || 'Command failed'
          })
        }
        
        return response
      } catch (error) {
        if (error instanceof TRPCError) throw error
        
        throw new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: error instanceof Error ? error.message : 'Unknown error'
        })
      }
    }),

  // Subscribe to agent status updates
  onStatusUpdate: publicProcedure.subscription(async function* ({ ctx }) {
    const manager = getAgentManager()
    
    // Send initial state
    yield manager.getAgents()
    
    // Listen for updates
    const onUpdate = (status: AgentStatus) => {
      void ctx.logger.debug('Agent status update', { agentId: status.id })
    }
    
    manager.on('agentStatus', onUpdate)
    
    try {
      // Keep subscription alive
      while (true) {
        await new Promise((resolve) => {
          const handler = () => {
            resolve(manager.getAgents())
          }
          manager.once('agentStatus', handler)
        })
        
        yield manager.getAgents()
      }
    } finally {
      manager.off('agentStatus', onUpdate)
    }
  }),

  // Start a service on an agent
  startService: publicProcedure
    .input(z.object({
      agentId: z.string(),
      serviceName: z.string()
    }))
    .mutation(async ({ input }) => {
      const manager = getAgentManager()
      
      return await manager.sendCommand(
        input.agentId,
        'service.start',
        { name: input.serviceName }
      )
    }),

  // Stop a service on an agent
  stopService: publicProcedure
    .input(z.object({
      agentId: z.string(),
      serviceName: z.string()
    }))
    .mutation(async ({ input }) => {
      const manager = getAgentManager()
      
      return await manager.sendCommand(
        input.agentId,
        'service.stop',
        { name: input.serviceName }
      )
    }),

  // Get service health on an agent
  serviceHealth: publicProcedure
    .input(z.object({
      agentId: z.string(),
      serviceName: z.string()
    }))
    .query(async ({ input }) => {
      const manager = getAgentManager()
      
      const response = await manager.sendCommand(
        input.agentId,
        'service.health',
        { name: input.serviceName }
      )
      
      return response.result
    })
})