/**
 * Client-side service configuration
 * Maps to the service-config package but uses environment variables
 * or window location for browser compatibility
 */

// Get the server port from environment or default
const SERVER_PORT = (import.meta.env.VITE_SERVER_PORT as string | undefined) || '7175'

// Get the server host from environment or use the configured host
const SERVER_HOST = (import.meta.env.VITE_SERVER_HOST as string | undefined) || 'saya'

// Build WebSocket URL based on configuration
export function getServerWebSocketUrl(): string {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${protocol}//${SERVER_HOST}:${SERVER_PORT}/`
}

// Build HTTP URL for API calls
export function getServerHttpUrl(): string {
  const protocol = window.location.protocol === 'https:' ? 'https:' : 'http:'
  return `${protocol}//${SERVER_HOST}:${SERVER_PORT}`
}

// Service URLs for client use
export const serviceUrls = {
  server: {
    ws: getServerWebSocketUrl(),
    http: getServerHttpUrl()
  }
}