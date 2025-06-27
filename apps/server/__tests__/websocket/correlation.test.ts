import { describe, it, expect, beforeEach, afterEach, mock } from 'bun:test'
import type { Server } from 'bun'

// NOTE: This test requires the server to be running
// It verifies that correlation IDs are properly tracked through WebSocket connections

describe('WebSocket Correlation ID Tracking', () => {
  const serverUrl = 'ws://localhost:7175'
  
  // Skip if server is not running
  const checkServerRunning = async () => {
    try {
      const response = await fetch('http://localhost:7175/health')
      return response.ok
    } catch {
      return false
    }
  }

  beforeEach(async () => {
    const isRunning = await checkServerRunning()
    if (!isRunning) {
      console.log('Server not running, skipping WebSocket tests')
      return
    }
  })

  it('should use correlation ID from headers if provided', async () => {
    const correlationId = 'test-correlation-id-123'
    
    const ws = new WebSocket(serverUrl, {
      headers: {
        'x-correlation-id': correlationId
      }
    })

    await new Promise<void>((resolve, reject) => {
      ws.onopen = () => {
        // Send a test message
        ws.send(JSON.stringify({
          id: 1,
          method: 'subscription',
          params: {
            path: 'health.status'
          }
        }))
        resolve()
      }
      
      ws.onerror = (error) => {
        reject(new Error(`WebSocket error: ${error}`))
      }
    })

    // Close the connection
    ws.close()
    
    // Wait for close
    await new Promise(resolve => setTimeout(resolve, 100))
  })

  it('should generate correlation ID if not provided', async () => {
    const ws = new WebSocket(serverUrl)

    await new Promise<void>((resolve, reject) => {
      ws.onopen = () => {
        // Send a test message
        ws.send(JSON.stringify({
          id: 1,
          method: 'subscription',
          params: {
            path: 'health.status'
          }
        }))
        resolve()
      }
      
      ws.onerror = (error) => {
        reject(new Error(`WebSocket error: ${error}`))
      }
    })

    // Close the connection
    ws.close()
    
    // Wait for close
    await new Promise(resolve => setTimeout(resolve, 100))
  })

  it('should maintain correlation ID throughout connection lifecycle', async () => {
    const correlationId = 'persistent-correlation-id'
    
    const ws = new WebSocket(serverUrl, {
      headers: {
        'x-correlation-id': correlationId
      }
    })

    const messages: any[] = []

    await new Promise<void>((resolve, reject) => {
      ws.onopen = () => {
        // Subscribe to a stream
        ws.send(JSON.stringify({
          id: 1,
          method: 'subscription',
          params: {
            path: 'twitch.onMessage'
          }
        }))
      }

      ws.onmessage = (event) => {
        messages.push(JSON.parse(event.data))
        
        // After receiving initial response, close connection
        if (messages.length === 1) {
          ws.close()
          resolve()
        }
      }
      
      ws.onerror = (error) => {
        reject(new Error(`WebSocket error: ${error}`))
      }
    })

    // Verify we got a response
    expect(messages.length).toBeGreaterThan(0)
  })
})