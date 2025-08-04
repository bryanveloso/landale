/**
 * WebSocket Message Inspector
 *
 * Provides message logging and inspection capabilities for debugging
 * WebSocket communication with Phoenix channels.
 */

export interface WebSocketMessage {
  id: string
  timestamp: number
  direction: 'incoming' | 'outgoing'
  channel?: string
  event?: string
  payload?: unknown
  ref?: string
  topic?: string
  raw?: string
}

export interface MessageFilter {
  direction?: 'incoming' | 'outgoing' | 'both'
  channel?: string
  event?: string
  search?: string
}

export class MessageInspector {
  private messages: WebSocketMessage[] = []
  private maxMessages: number
  private enabled = false
  private listeners: Array<(message: WebSocketMessage) => void> = []

  constructor(maxMessages = 100) {
    this.maxMessages = maxMessages
  }

  /**
   * Enable or disable message inspection
   */
  setEnabled(enabled: boolean) {
    this.enabled = enabled
    if (!enabled) {
      this.clear()
    }
  }

  /**
   * Check if inspection is enabled
   */
  isEnabled(): boolean {
    return this.enabled
  }

  /**
   * Record an incoming message
   */
  recordIncoming(data: any) {
    if (!this.enabled) return

    const message: WebSocketMessage = {
      id: this.generateId(),
      timestamp: Date.now(),
      direction: 'incoming',
      raw: typeof data === 'string' ? data : JSON.stringify(data)
    }

    // Try to parse Phoenix message format
    if (typeof data === 'object' && data !== null) {
      message.topic = data.topic
      message.event = data.event
      message.payload = data.payload
      message.ref = data.ref

      // Extract channel from topic if present
      if (data.topic) {
        const parts = data.topic.split(':')
        message.channel = parts[0]
      }
    }

    this.addMessage(message)
  }

  /**
   * Record an outgoing message
   */
  recordOutgoing(data: any) {
    if (!this.enabled) return

    const message: WebSocketMessage = {
      id: this.generateId(),
      timestamp: Date.now(),
      direction: 'outgoing',
      raw: typeof data === 'string' ? data : JSON.stringify(data)
    }

    // Try to parse Phoenix message format
    if (typeof data === 'object' && data !== null) {
      message.topic = data.topic
      message.event = data.event
      message.payload = data.payload
      message.ref = data.ref

      // Extract channel from topic if present
      if (data.topic) {
        const parts = data.topic.split(':')
        message.channel = parts[0]
      }
    }

    this.addMessage(message)
  }

  /**
   * Get all messages with optional filtering
   */
  getMessages(filter?: MessageFilter): WebSocketMessage[] {
    if (!filter) {
      return [...this.messages]
    }

    return this.messages.filter((msg) => {
      // Direction filter
      if (filter.direction && filter.direction !== 'both' && msg.direction !== filter.direction) {
        return false
      }

      // Channel filter
      if (filter.channel && msg.channel !== filter.channel) {
        return false
      }

      // Event filter
      if (filter.event && msg.event !== filter.event) {
        return false
      }

      // Search filter (searches in raw message)
      if (filter.search && msg.raw && !msg.raw.toLowerCase().includes(filter.search.toLowerCase())) {
        return false
      }

      return true
    })
  }

  /**
   * Get message count
   */
  getCount(): number {
    return this.messages.length
  }

  /**
   * Clear all messages
   */
  clear() {
    this.messages = []
    this.notifyListeners()
  }

  /**
   * Subscribe to message updates
   */
  subscribe(listener: (message: WebSocketMessage) => void) {
    this.listeners.push(listener)
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener)
    }
  }

  /**
   * Get message statistics
   */
  getStats() {
    const total = this.messages.length
    const incoming = this.messages.filter((m) => m.direction === 'incoming').length
    const outgoing = this.messages.filter((m) => m.direction === 'outgoing').length

    // Count by channel
    const byChannel: Record<string, number> = {}
    this.messages.forEach((msg) => {
      if (msg.channel) {
        byChannel[msg.channel] = (byChannel[msg.channel] || 0) + 1
      }
    })

    // Count by event
    const byEvent: Record<string, number> = {}
    this.messages.forEach((msg) => {
      if (msg.event) {
        byEvent[msg.event] = (byEvent[msg.event] || 0) + 1
      }
    })

    return {
      total,
      incoming,
      outgoing,
      byChannel,
      byEvent,
      oldestMessage: this.messages[0]?.timestamp,
      newestMessage: this.messages[this.messages.length - 1]?.timestamp
    }
  }

  /**
   * Export messages as JSON
   */
  exportAsJson(): string {
    return JSON.stringify(this.messages, null, 2)
  }

  private addMessage(message: WebSocketMessage) {
    this.messages.push(message)

    // Maintain max size
    if (this.messages.length > this.maxMessages) {
      this.messages.shift()
    }

    // Notify listeners
    this.notifyListeners(message)
  }

  private notifyListeners(message?: WebSocketMessage) {
    if (message) {
      this.listeners.forEach((listener) => listener(message))
    }
  }

  private generateId(): string {
    return `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  }
}
