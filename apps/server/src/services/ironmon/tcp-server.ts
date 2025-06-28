import type { TCPSocketListener, Socket } from 'bun'
import chalk from 'chalk'
import { createLogger } from '@landale/logger'
import { SERVICE_CONFIG } from '@landale/service-config'
import { ironmonMessageSchema } from './types'
import { handleCheckpoint, handleInit, handleSeed, handleLocation } from './handlers'

interface TCPServerOptions {
  port?: number
  hostname?: string
}

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'ironmon-tcp' })

export class IronmonTCPServer {
  private server?: TCPSocketListener
  private buffer = new Map<Socket<unknown>, string>()
  private options: Required<TCPServerOptions>

  constructor(options: TCPServerOptions = {}) {
    const tcpPort = SERVICE_CONFIG.server.ports.tcp || 8080
    this.options = {
      port: options.port ?? tcpPort,
      hostname: options.hostname ?? '0.0.0.0'
    }
  }

  /**
   * Handles incoming socket connections
   */
  private handleOpen = (socket: Socket<unknown>) => {
    log.info('TCP client connected', { metadata: { remoteAddress: socket.remoteAddress } })
    this.buffer.set(socket, '')
  }

  /**
   * Handles incoming data from the socket
   * Messages are length-prefixed: "LENGTH MESSAGE" (e.g., "23 {"type":"init",...}")
   */
  private handleData = async (socket: Socket<unknown>, data: Buffer) => {
    // Get or create buffer for this socket
    let buffer = this.buffer.get(socket) || ''
    buffer += data.toString('utf-8')

    // Process all complete messages in the buffer
    while (buffer.length > 0) {
      // Find the space that separates length from message
      const spaceIndex = buffer.indexOf(' ')
      if (spaceIndex === -1) {
        break // Wait for more data
      }

      // Parse the message length
      const lengthStr = buffer.slice(0, spaceIndex)
      const length = parseInt(lengthStr, 10)

      if (isNaN(length)) {
        log.error('Invalid message length', { metadata: { lengthStr } })
        buffer = ''
        break
      }

      // Check if we have the complete message
      const messageStart = spaceIndex + 1
      const messageEnd = messageStart + length

      if (buffer.length < messageEnd) {
        break // Wait for more data
      }

      // Extract and process the message
      const messageStr = buffer.slice(messageStart, messageEnd)

      try {
        await this.processMessage(messageStr)
      } catch (error) {
        log.error('Error processing message', { error: error as Error })
      }

      // Remove processed message from buffer
      buffer = buffer.slice(messageEnd)
    }

    // Update buffer for this socket
    this.buffer.set(socket, buffer)
  }

  /**
   * Processes a single IronMON message
   */
  private async processMessage(messageStr: string) {
    let parsedMessage: unknown
    try {
      parsedMessage = JSON.parse(messageStr)
    } catch {
      log.error('Failed to parse JSON', { metadata: { message: messageStr } })
      return
    }

    // Parse and validate the message
    const parseResult = ironmonMessageSchema.safeParse(parsedMessage)

    if (!parseResult.success) {
      log.error('Invalid IronMON message', {
        error: new Error('Validation failed'),
        metadata: { errors: parseResult.error.format() }
      })
      return
    }

    const message = parseResult.data
    log.debug('IronMON message received', {
      metadata: { type: message.type, messageMetadata: message.metadata }
    })

    // Route to appropriate handler based on message type
    switch (message.type) {
      case 'init':
        handleInit(message)
        break
      case 'seed':
        await handleSeed(message)
        break
      case 'checkpoint':
        await handleCheckpoint(message)
        break
      case 'location':
        handleLocation(message)
        break
    }
  }

  /**
   * Handles socket closure
   */
  private handleClose = (socket: Socket<unknown>) => {
    log.info('TCP client disconnected', { metadata: { remoteAddress: socket.remoteAddress } })
    this.buffer.delete(socket)
  }

  /**
   * Handles socket errors
   */
  private handleError = (socket: Socket<unknown>, error: Error) => {
    log.error('TCP socket error', {
      error: error,
      metadata: { remoteAddress: socket.remoteAddress }
    })
  }

  /**
   * Starts the TCP server
   */
  start(): void {
    if (this.server) {
      throw new Error('TCP server is already running')
    }

    this.server = Bun.listen({
      hostname: this.options.hostname,
      port: this.options.port,
      socket: {
        open: this.handleOpen,
        data: this.handleData,
        close: this.handleClose,
        error: this.handleError
      }
    })

    console.log(
      `  ${chalk.green('➜')}  ${chalk.bold('IronMON TCP Server')}: ${this.options.hostname}:${this.options.port.toString()}`
    )
    log.info('IronMON TCP Server started', {
      metadata: { hostname: this.options.hostname, port: this.options.port }
    })
  }

  /**
   * Stops the TCP server
   */
  stop(): void {
    if (this.server) {
      this.server.stop()
      this.server = undefined
      this.buffer.clear()
      log.info('IronMON TCP Server stopped')
    }
  }
}

// Export a singleton instance
export const ironmonTCPServer = new IronmonTCPServer()
