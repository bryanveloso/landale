#!/usr/bin/env node
/**
 * PM2 HTTP Agent - Enables remote PM2 control via HTTP API
 * Node.js version for Windows machines
 */

const http = require('http')
const pm2 = require('pm2')
const url = require('url')

const PORT = parseInt(process.env.PM2_AGENT_PORT || '9615')
const HOST = process.env.PM2_AGENT_HOST || '0.0.0.0'
const AUTH_TOKEN = process.env.PM2_AGENT_TOKEN || 'change-me-in-production'

// Connect to local PM2
pm2.connect((err) => {
  if (err) {
    console.error('Failed to connect to PM2:', err)
    process.exit(2)
  }
  console.log('Connected to PM2')
})

// Create HTTP server
const server = http.createServer(async (req, res) => {
  const parsedUrl = url.parse(req.url, true)
  
  // Check authentication
  const authHeader = req.headers.authorization
  if (!authHeader || authHeader !== `Bearer ${AUTH_TOKEN}`) {
    res.writeHead(401, { 'Content-Type': 'text/plain' })
    res.end('Unauthorized')
    return
  }
  
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type')
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200)
    res.end()
    return
  }
  
  // Route handlers
  if (req.method === 'GET' && parsedUrl.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ status: 'ok', timestamp: new Date().toISOString() }))
    return
  }
  
  if (req.method === 'GET' && parsedUrl.pathname === '/processes') {
    handleList(res)
    return
  }
  
  if (req.method === 'POST' && parsedUrl.pathname.startsWith('/process/')) {
    const parts = parsedUrl.pathname.split('/')
    const processName = decodeURIComponent(parts[2])
    const action = parts[3]
    
    switch (action) {
      case 'start':
        handleStart(processName, res)
        return
      case 'stop':
        handleStop(processName, res)
        return
      case 'restart':
        handleRestart(processName, res)
        return
      case 'describe':
        handleDescribe(processName, res)
        return
      default:
        res.writeHead(400, { 'Content-Type': 'text/plain' })
        res.end('Invalid action')
        return
    }
  }
  
  if (req.method === 'POST' && parsedUrl.pathname === '/flush') {
    const processName = parsedUrl.query.process
    handleFlush(processName, res)
    return
  }
  
  res.writeHead(404, { 'Content-Type': 'text/plain' })
  res.end('Not Found')
})

server.listen(PORT, HOST, () => {
  console.log(`PM2 Agent listening on ${HOST}:${PORT}`)
})

// Handler functions
function handleList(res) {
  pm2.list((err, processDescriptionList) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
      return
    }
    
    const processes = processDescriptionList.map((proc) => ({
      name: proc.name || 'unknown',
      pm_id: proc.pm_id || 0,
      status: proc.pm2_env?.status || 'stopped',
      cpu: proc.monit?.cpu || 0,
      memory: proc.monit?.memory || 0,
      uptime: proc.pm2_env?.pm_uptime || 0,
      restart_time: proc.pm2_env?.restart_time || 0,
      unstable_restarts: proc.pm2_env?.unstable_restarts || 0
    }))
    
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify(processes))
  })
}

function handleStart(processName, res) {
  pm2.start(processName, (err) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
      return
    }
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ success: true }))
  })
}

function handleStop(processName, res) {
  pm2.stop(processName, (err) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
      return
    }
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ success: true }))
  })
}

function handleRestart(processName, res) {
  pm2.restart(processName, (err) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
      return
    }
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ success: true }))
  })
}

function handleDescribe(processName, res) {
  pm2.describe(processName, (err, processDescription) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
      return
    }
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify(processDescription))
  })
}

function handleFlush(processName, res) {
  if (processName) {
    pm2.flush(processName, (err) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ error: err.message }))
        return
      }
      res.writeHead(200, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ success: true }))
    })
  } else {
    // Flush all
    pm2.list((err, processes) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ error: err.message }))
        return
      }
      
      let flushCount = 0
      const totalProcesses = processes.length
      
      if (totalProcesses === 0) {
        res.writeHead(200, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ success: true, flushed: 0 }))
        return
      }
      
      processes.forEach((proc) => {
        pm2.flush(proc.pm_id || 0, (flushErr) => {
          flushCount++
          if (flushErr) {
            res.writeHead(500, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({ error: flushErr.message }))
            return
          }
          if (flushCount === totalProcesses) {
            res.writeHead(200, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({ success: true, flushed: totalProcesses }))
          }
        })
      })
    })
  }
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Shutting down PM2 Agent...')
  pm2.disconnect()
  server.close()
  process.exit(0)
})

process.on('SIGTERM', () => {
  console.log('Shutting down PM2 Agent...')
  pm2.disconnect()
  server.close()
  process.exit(0)
})