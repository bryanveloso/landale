#!/usr/bin/env bun
/**
 * PM2 HTTP Agent - Enables remote PM2 control via HTTP API
 * This runs on each machine to expose PM2 commands safely
 */

import pm2 from 'pm2'

const PORT = parseInt(process.env.PM2_AGENT_PORT || '9615')
const HOST = process.env.PM2_AGENT_HOST || '0.0.0.0'
const AUTH_TOKEN = process.env.PM2_AGENT_TOKEN || 'change-me-in-production'

interface ProcessInfo {
  name: string
  pm_id: number
  status: 'online' | 'stopping' | 'stopped' | 'launching' | 'errored'
  cpu: number
  memory: number
  uptime: number
  restart_time: number
  unstable_restarts: number
}

// Connect to local PM2
pm2.connect((err) => {
  if (err) {
    console.error('Failed to connect to PM2:', err)
    process.exit(2)
  }
  console.log('Connected to PM2')
})

// Create HTTP server
const server = Bun.serve({
  port: PORT,
  hostname: HOST,
  
  fetch(request) {
    const url = new URL(request.url)
    
    // Check authentication
    const authHeader = request.headers.get('Authorization')
    if (!authHeader || authHeader !== `Bearer ${AUTH_TOKEN}`) {
      return new Response('Unauthorized', { status: 401 })
    }
    
    // Route handlers
    if (request.method === 'GET' && url.pathname === '/health') {
      return Response.json({ status: 'ok', timestamp: new Date().toISOString() })
    }
    
    if (request.method === 'GET' && url.pathname === '/processes') {
      return handleList()
    }
    
    if (request.method === 'POST' && url.pathname.startsWith('/process/')) {
      const parts = url.pathname.split('/')
      const processName = parts[2]
      const action = parts[3]
      
      switch (action) {
        case 'start':
          return handleStart(processName)
        case 'stop':
          return handleStop(processName)
        case 'restart':
          return handleRestart(processName)
        case 'describe':
          return handleDescribe(processName)
        default:
          return new Response('Invalid action', { status: 400 })
      }
    }
    
    if (request.method === 'POST' && url.pathname === '/flush') {
      const processName = url.searchParams.get('process')
      return handleFlush(processName)
    }
    
    return new Response('Not Found', { status: 404 })
  }
})

console.log(`PM2 Agent listening on ${HOST}:${PORT}`)

// Handler functions
async function handleList(): Promise<Response> {
  return new Promise((resolve) => {
    pm2.list((err, processDescriptionList) => {
      if (err) {
        resolve(Response.json({ error: err.message }, { status: 500 }))
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
      
      resolve(Response.json(processes))
    })
  })
}

async function handleStart(processName: string): Promise<Response> {
  return new Promise((resolve) => {
    pm2.start(processName, (err) => {
      if (err) {
        resolve(Response.json({ error: err.message }, { status: 500 }))
        return
      }
      resolve(Response.json({ success: true }))
    })
  })
}

async function handleStop(processName: string): Promise<Response> {
  return new Promise((resolve) => {
    pm2.stop(processName, (err) => {
      if (err) {
        resolve(Response.json({ error: err.message }, { status: 500 }))
        return
      }
      resolve(Response.json({ success: true }))
    })
  })
}

async function handleRestart(processName: string): Promise<Response> {
  return new Promise((resolve) => {
    pm2.restart(processName, (err) => {
      if (err) {
        resolve(Response.json({ error: err.message }, { status: 500 }))
        return
      }
      resolve(Response.json({ success: true }))
    })
  })
}

async function handleDescribe(processName: string): Promise<Response> {
  return new Promise((resolve) => {
    pm2.describe(processName, (err, processDescription) => {
      if (err) {
        resolve(Response.json({ error: err.message }, { status: 500 }))
        return
      }
      resolve(Response.json(processDescription))
    })
  })
}

async function handleFlush(processName: string | null): Promise<Response> {
  return new Promise((resolve) => {
    if (processName) {
      pm2.flush(processName, (err) => {
        if (err) {
          resolve(Response.json({ error: err.message }, { status: 500 }))
          return
        }
        resolve(Response.json({ success: true }))
      })
    } else {
      // Flush all
      pm2.list((err, processes) => {
        if (err) {
          resolve(Response.json({ error: err.message }, { status: 500 }))
          return
        }
        
        let flushCount = 0
        const totalProcesses = processes.length
        
        if (totalProcesses === 0) {
          resolve(Response.json({ success: true, flushed: 0 }))
          return
        }
        
        processes.forEach((proc) => {
          pm2.flush(proc.pm_id || 0, (flushErr) => {
            flushCount++
            if (flushErr) {
              resolve(Response.json({ error: flushErr.message }, { status: 500 }))
              return
            }
            if (flushCount === totalProcesses) {
              resolve(Response.json({ success: true, flushed: totalProcesses }))
            }
          })
        })
      })
    }
  })
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down PM2 Agent...')
  pm2.disconnect()
  process.exit(0)
})

process.on('SIGTERM', () => {
  console.log('Shutting down PM2 Agent...')
  pm2.disconnect()
  process.exit(0)
})