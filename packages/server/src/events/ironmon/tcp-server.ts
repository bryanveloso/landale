import type { Server, TCPSocketListener, Socket } from 'bun'
import chalk from 'chalk'
import { ironmonMessageSchema } from './types'
import { handleCheckpoint, handleInit, handleSeed } from './handlers'

interface TCPServerOptions {
  port?: number
  hostname?: string
}

export class IronmonTCPServer {
  private server?: TCPSocketListener
  private buffer = new Map<Socket<unknown>, string>()
  private options: Required<TCPServerOptions>

  constructor(options: TCPServerOptions = {}) {
    this.options = {
      port: options.port ?? 8080,
      hostname: options.hostname ?? '0.0.0.0'
    }
  }

  /**
   * Handles incoming socket connections
   */
  private handleOpen = (socket: Socket<unknown>) => {
    console.log(`  ${chalk.green('→')}  TCP client connected: ${socket.remoteAddress}`)
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
        console.error(`  ${chalk.red('✗')}  Invalid message length: ${lengthStr}`)
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
        console.error(`  ${chalk.red('✗')}  Error processing message:`, error)
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
    // Parse and validate the message
    const parseResult = ironmonMessageSchema.safeParse(JSON.parse(messageStr))

    if (!parseResult.success) {
      console.error(`  ${chalk.red('✗')}  Invalid IronMON message:`, parseResult.error.format())
      return
    }

    const message = parseResult.data
    console.log(`  ${chalk.blue('◆')}  IronMON ${message.type}: ${JSON.stringify(message.metadata)}`)

    // Route to appropriate handler based on message type
    switch (message.type) {
      case 'init':
        await handleInit(message)
        break
      case 'seed':
        await handleSeed(message)
        break
      case 'checkpoint':
        await handleCheckpoint(message)
        break
    }
  }

  /**
   * Handles socket closure
   */
  private handleClose = (socket: Socket<unknown>) => {
    console.log(`  ${chalk.yellow('←')}  TCP client disconnected: ${socket.remoteAddress}`)
    this.buffer.delete(socket)
  }

  /**
   * Handles socket errors
   */
  private handleError = (socket: Socket<unknown>, error: Error) => {
    console.error(`  ${chalk.red('✗')}  TCP socket error from ${socket.remoteAddress}:`, error.message)
  }

  /**
   * Starts the TCP server
   */
  async start(): Promise<void> {
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
      `  ${chalk.green('➜')}  ${chalk.bold('IronMON TCP Server')}: ${this.options.hostname}:${this.options.port}`
    )
  }

  /**
   * Stops the TCP server
   */
  async stop(): Promise<void> {
    if (this.server) {
      this.server.stop()
      this.server = undefined
      this.buffer.clear()
      console.log(`  ${chalk.yellow('•')}  IronMON TCP Server stopped`)
    }
  }
}

// Export a singleton instance
export const ironmonTCPServer = new IronmonTCPServer()
