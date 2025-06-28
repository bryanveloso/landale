#!/usr/bin/env bun
import { MacOSAgent } from '../macos-agent'
import { ServiceRegistry } from '@landale/service-config'

// Create service registry instance
const serviceRegistry = new ServiceRegistry()

// Create agent for zelan (Mac Studio)
const agent = new MacOSAgent({
  id: 'zelan',
  name: 'Zelan AI Services Agent',
  host: 'zelan',
  serverUrl: serviceRegistry.getUrl('server')
})

// Register services running on zelan
agent.registerService({
  name: 'phononmaser',
  type: 'process',
  processName: 'python.*phononmaser',
  healthCheck: async () => {
    try {
      const response = await fetch('http://localhost:8889/health')
      return response.ok
    } catch {
      return false
    }
  }
})

agent.registerService({
  name: 'analysis',
  type: 'process',
  processName: 'python.*analysis',
  healthCheck: async () => {
    try {
      const response = await fetch('http://localhost:8890/health')
      return response.ok
    } catch {
      return false
    }
  }
})

agent.registerService({
  name: 'lmstudio',
  type: 'process',
  processName: 'LM Studio',
  healthCheck: async () => {
    try {
      const response = await fetch(`${serviceRegistry.getUrl('lms')}/models`)
      return response.ok
    } catch {
      return false
    }
  }
})

// Start the agent
agent.start().catch(console.error)

// Handle shutdown
process.on('SIGINT', async () => {
  console.log('Shutting down agent...')
  await agent.stop()
  process.exit(0)
})