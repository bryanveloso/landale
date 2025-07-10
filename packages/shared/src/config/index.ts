/**
 * Shared configuration constants
 */

export const DEFAULT_SERVER_URLS = {
  WS_PORT: 7175,
  HTTP_PORT: 8080,
  
  // Generate WebSocket URLs based on environment
  getWebSocketUrl: (hostname: string = window.location.hostname): string => {
    if (hostname === 'localhost') {
      return `ws://localhost:${DEFAULT_SERVER_URLS.WS_PORT}/socket`
    }
    return `ws://zelan:${DEFAULT_SERVER_URLS.WS_PORT}/socket`
  },
  
  // Generate HTTP URLs based on environment
  getHttpUrl: (hostname: string = window.location.hostname): string => {
    if (hostname === 'localhost') {
      return `http://localhost:${DEFAULT_SERVER_URLS.HTTP_PORT}`
    }
    return `http://zelan:${DEFAULT_SERVER_URLS.HTTP_PORT}`
  }
}