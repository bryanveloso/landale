#!/usr/bin/env bun

/**
 * Health check script for Stream Deck or automation
 * Returns exit code 0 if healthy, 1 if unhealthy
 * 
 * Usage: bun run scripts/check-health.ts
 */

const HEALTH_URL = 'http://localhost:7175/health'
const TIMEOUT = 3000 // 3 seconds

async function checkHealth() {
  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), TIMEOUT)
    
    const response = await fetch(HEALTH_URL, {
      signal: controller.signal
    })
    
    clearTimeout(timeoutId)
    
    if (!response.ok) {
      console.error(`Health check failed: HTTP ${response.status}`)
      process.exit(1)
    }
    
    const data = await response.json()
    
    if (data.status === 'ok') {
      // Output simple status for Stream Deck
      console.log('✓ ONLINE')
      
      // Also output detailed info to stderr so it doesn't interfere
      const uptime = Math.floor(data.uptime)
      const hours = Math.floor(uptime / 3600)
      const minutes = Math.floor((uptime % 3600) / 60)
      console.error(`Uptime: ${hours}h ${minutes}m`)
      console.error(`Version: ${data.version}`)
      
      process.exit(0)
    } else {
      console.error('✗ UNHEALTHY')
      process.exit(1)
    }
  } catch (error) {
    if (error.name === 'AbortError') {
      console.error('✗ TIMEOUT')
    } else {
      console.error('✗ OFFLINE')
    }
    console.error(error.message)
    process.exit(1)
  }
}

checkHealth()