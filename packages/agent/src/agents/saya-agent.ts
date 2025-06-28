#!/usr/bin/env bun
import { MacOSAgent } from '../macos-agent'
import { ServiceRegistry } from '@landale/service-config'

// Create service registry instance
const serviceRegistry = new ServiceRegistry()

// Create agent for saya (Mac Mini)
const agent = new MacOSAgent({
  id: 'saya',
  name: 'Saya Services Agent',
  host: 'saya',
  serverUrl: serviceRegistry.getUrl('server')
})

// Register services running on saya
agent.registerService({
  name: 'server',
  type: 'docker',
  dockerService: 'server',
  healthCheck: async () => {
    try {
      const response = await fetch(`${serviceRegistry.getUrl('server')}/health`)
      return response.ok
    } catch {
      return false
    }
  }
})

agent.registerService({
  name: 'overlays',
  type: 'docker',
  dockerService: 'overlays',
  healthCheck: async () => {
    try {
      const response = await fetch('http://localhost:8008')
      return response.ok
    } catch {
      return false
    }
  }
})

agent.registerService({
  name: 'postgres',
  type: 'docker',
  dockerService: 'db'
})

agent.registerService({
  name: 'seq',
  type: 'docker',
  dockerService: 'seq'
})

// Start the agent
agent.start().catch(console.error)

// Handle shutdown
process.on('SIGINT', async () => {
  console.log('Shutting down agent...')
  await agent.stop()
  process.exit(0)
})