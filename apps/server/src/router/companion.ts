/**
 * Companion HTTP endpoints for Stream Deck integration
 * These are simple HTTP endpoints that Companion can call
 */

import type { Server } from 'bun'
import { pm2Manager } from '@/services/pm2-manager'
import { createLogger } from '@landale/logger'

const log = createLogger({ service: 'companion-api' })

export function registerCompanionEndpoints(server: Server) {
  // This would be called from your main server setup
  // For now, we'll document the endpoints that need to be created
}

/**
 * Companion-friendly HTTP endpoints to add to your server:
 * 
 * GET /api/companion/process/:machine/:process/status
 * - Returns: { status: 'online' | 'stopped', cpu: number, memory: number }
 * 
 * POST /api/companion/process/:machine/:process/start
 * - Returns: { success: boolean }
 * 
 * POST /api/companion/process/:machine/:process/stop
 * - Returns: { success: boolean }
 * 
 * POST /api/companion/process/:machine/:process/restart
 * - Returns: { success: boolean }
 * 
 * GET /api/companion/process/:machine/list
 * - Returns: [{ name: string, status: string, cpu: number, memory: number }]
 */

// Helper functions for Companion endpoints
export async function getProcessStatus(machine: string, processName: string) {
  try {
    const processes = await pm2Manager.list(machine)
    const process = processes.find(p => p.name === processName)
    
    if (!process) {
      return { status: 'not_found', cpu: 0, memory: 0 }
    }
    
    return {
      status: process.status,
      cpu: process.cpu,
      memory: process.memory
    }
  } catch (error) {
    log.error('Failed to get process status', { 
      error: error instanceof Error ? { message: error.message } : { message: String(error) },
      metadata: { machine, processName }
    })
    return { status: 'error', cpu: 0, memory: 0 }
  }
}

export async function startProcess(machine: string, processName: string) {
  try {
    await pm2Manager.start(machine, processName)
    return { success: true }
  } catch (error) {
    log.error('Failed to start process', { 
      error: error instanceof Error ? { message: error.message } : { message: String(error) },
      metadata: { machine, processName }
    })
    return { success: false, error: error instanceof Error ? error.message : 'Unknown error' }
  }
}

export async function stopProcess(machine: string, processName: string) {
  try {
    await pm2Manager.stop(machine, processName)
    return { success: true }
  } catch (error) {
    log.error('Failed to stop process', { 
      error: error instanceof Error ? { message: error.message } : { message: String(error) },
      metadata: { machine, processName }
    })
    return { success: false, error: error instanceof Error ? error.message : 'Unknown error' }
  }
}

export async function restartProcess(machine: string, processName: string) {
  try {
    await pm2Manager.restart(machine, processName)
    return { success: true }
  } catch (error) {
    log.error('Failed to restart process', { 
      error: error instanceof Error ? { message: error.message } : { message: String(error) },
      metadata: { machine, processName }
    })
    return { success: false, error: error instanceof Error ? error.message : 'Unknown error' }
  }
}

export async function listProcesses(machine: string) {
  try {
    const processes = await pm2Manager.list(machine)
    return processes.map(p => ({
      name: p.name,
      status: p.status,
      cpu: p.cpu,
      memory: p.memory,
      uptime: p.uptime
    }))
  } catch (error) {
    log.error('Failed to list processes', { 
      error: error instanceof Error ? { message: error.message } : { message: String(error) },
      metadata: { machine }
    })
    return []
  }
}