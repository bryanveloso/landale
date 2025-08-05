/**
 * WebSocket Configuration Constants
 *
 * These constants define the default configuration for WebSocket connections
 * across the Landale system. They ensure consistent behavior and proper
 * heartbeat/timeout ratios to prevent disconnection issues.
 */

/**
 * Default WebSocket configuration values
 *
 * IMPORTANT: The heartbeat interval must be significantly less than the server timeout
 * to account for network latency, browser throttling, and processing delays.
 *
 * With a server timeout of 90 seconds, a 15-second heartbeat provides a 6x safety factor.
 */
export const WEBSOCKET_DEFAULTS = {
  // Connection retry settings
  MAX_RECONNECT_ATTEMPTS: 10,
  RECONNECT_DELAY_BASE: 1000, // 1 second
  RECONNECT_DELAY_CAP: 30000, // 30 seconds

  // Heartbeat settings
  HEARTBEAT_INTERVAL: 15000, // 15 seconds (6x safety factor with 90s server timeout)

  // Circuit breaker settings
  CIRCUIT_BREAKER_THRESHOLD: 5,
  CIRCUIT_BREAKER_TIMEOUT: 300000, // 5 minutes

  // Message inspector settings
  MESSAGE_INSPECTOR_BUFFER_SIZE: 100
} as const

/**
 * Server-side timeout configuration
 * This should match the Phoenix endpoint configuration
 */
export const SERVER_WEBSOCKET_TIMEOUT = 90000 // 90 seconds

/**
 * Calculate the safety factor for heartbeat configuration
 */
export const HEARTBEAT_SAFETY_FACTOR = SERVER_WEBSOCKET_TIMEOUT / WEBSOCKET_DEFAULTS.HEARTBEAT_INTERVAL // Should be >= 6
