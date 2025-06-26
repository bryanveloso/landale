import { WebSocketServer, WebSocket as WSWebSocket } from 'ws'
import { logger } from '@lib/logger'
import { AudioProcessor } from '@services/audio-processor'
import { eventEmitter } from '@events'
import { LMStudioService } from '@services/lm-studio-service'
import { z } from 'zod'

// Message schemas
const _AudioDataMessageSchema = z.object({
  type: z.literal('audio_data'),
  timestamp: z.number(),
  format: z.object({
    sampleRate: z.number(),
    channels: z.number(),
    bitDepth: z.number()
  }),
  data: z.string(), // Base64 encoded data
  sourceId: z.string(),
  sourceName: z.string()
})

const _ControlMessageSchema = z.object({
  type: z.enum(['start', 'stop', 'heartbeat']),
  timestamp: z.number()
})

type AudioDataMessage = z.infer<typeof _AudioDataMessageSchema>
type ControlMessage = z.infer<typeof _ControlMessageSchema>

// Environment configuration
const PORT = process.env.PHONONMASER_PORT ? parseInt(process.env.PHONONMASER_PORT) : 8889

export class Phononmaser {
  private wss: WebSocketServer
  private processor: AudioProcessor
  private lmStudioService?: LMStudioService
  private clients = new Set<WSWebSocket>()
  private headerLogged = false
  private packetCounter = 0

  constructor() {
    this.processor = new AudioProcessor()
    this.wss = new WebSocketServer({ port: PORT })
    this.setupWebSocket()
    this.initializeLMStudio()
    logger.info(`Phononmaser started on port ${PORT.toString()}`)
  }

  private initializeLMStudio() {
    try {
      // Check if LM Studio is configured
      const lmStudioUrl = process.env.LM_STUDIO_API_URL
      const lmStudioModel = process.env.LM_STUDIO_MODEL

      if (lmStudioUrl) {
        this.lmStudioService = new LMStudioService({
          apiUrl: lmStudioUrl,
          model: lmStudioModel || 'local-model'
        })

        logger.info('LM Studio integration enabled')
      } else {
        logger.info('LM Studio not configured, AI analysis disabled')
      }
    } catch (error) {
      logger.error('Failed to initialize LM Studio:', error)
    }
  }

  private setupWebSocket() {
    this.wss.on('connection', (ws) => {
      logger.info('New audio source connected')
      this.clients.add(ws)

      ws.on('message', (data) => {
        try {
          // Check if it's binary data
          if (data instanceof Buffer) {
            // Minimum size check
            if (data.length < 28) {
              logger.error('Binary message too small for header:', data.length)
              return
            }

            // Parse OBS plugin binary format
            let offset = 0

            // Parse header (28 bytes)
            const timestamp = data.readBigUInt64LE(offset)
            offset += 8
            const sampleRate = data.readUInt32LE(offset)
            offset += 4
            const channels = data.readUInt32LE(offset)
            offset += 4
            const bitDepth = data.readUInt32LE(offset)
            offset += 4
            const sourceIdLen = data.readUInt32LE(offset)
            offset += 4
            const sourceNameLen = data.readUInt32LE(offset)
            offset += 4

            // Only log header once per connection
            if (!this.headerLogged) {
              logger.debug(
                `Header: timestamp=${timestamp.toString()}, rate=${sampleRate.toString()}, ch=${channels.toString()}, sourceIdLen=${sourceIdLen.toString()}, sourceNameLen=${sourceNameLen.toString()}`
              )
              this.headerLogged = true
            }

            // Parse strings
            const sourceId = data.toString('utf8', offset, offset + sourceIdLen)
            offset += sourceIdLen
            const sourceName = data.toString('utf8', offset, offset + sourceNameLen)
            offset += sourceNameLen

            // Extract audio data (rest of buffer)
            const audioData = data.subarray(offset)

            // Log every 100th packet to reduce spam
            if (!this.packetCounter) this.packetCounter = 0
            if (this.packetCounter++ % 100 === 0) {
              logger.debug(
                `Audio packet: ${sampleRate.toString()}Hz, ${channels.toString()}ch, ${bitDepth.toString()}bit, ${audioData.length.toString()} bytes from ${sourceName}`
              )
            }

            // Validate header values
            if (sampleRate > 192000 || channels > 8 || bitDepth > 32) {
              logger.error('Invalid header values, skipping packet')
              return
            }

            // Auto-start processor if not running
            if (!this.processor.isReceiving()) {
              logger.info('Auto-starting audio processor')
              this.processor.start()
            }

            // Process the audio chunk
            this.processor.processChunk({
              timestamp: Number(timestamp) / 1000, // Convert nanoseconds to microseconds
              format: {
                sampleRate,
                channels,
                bitDepth
              },
              data: audioData,
              sourceId
            })

            // Emit event for monitoring
            eventEmitter.emit('audio:chunk', {
              timestamp: Number(timestamp) / 1000,
              sourceId,
              sourceName,
              size: audioData.length
            })

            return
          }

          // Parse JSON message
          let dataStr: string
          if (data instanceof Buffer) {
            dataStr = data.toString('utf8')
          } else if (data instanceof ArrayBuffer) {
            dataStr = Buffer.from(data).toString('utf8')
          } else if (typeof data === 'string') {
            dataStr = data
          } else {
            logger.error('Unsupported data type for JSON parsing')
            return
          }
          const message = JSON.parse(dataStr) as unknown
          
          // Validate message type
          if (typeof message === 'object' && message !== null && 'type' in message) {
            const msgType = (message as { type: unknown }).type
            
            if (msgType === 'audio_data') {
              const result = _AudioDataMessageSchema.safeParse(message)
              if (result.success) {
                this.handleAudioData(result.data)
              } else {
                logger.error('Invalid audio data message:', result.error)
              }
            } else if (msgType === 'start' || msgType === 'stop' || msgType === 'heartbeat') {
              const result = _ControlMessageSchema.safeParse(message)
              if (result.success) {
                this.handleControlMessage(result.data)
              } else {
                logger.error('Invalid control message:', result.error)
              }
            }
          }
          } catch (error) {
            logger.error('Error processing message:', error)
            logger.error('Message type:', typeof data)
            const preview = data instanceof Buffer ? data.toString('utf8', 0, Math.min(200, data.length)) : 'Non-buffer data'
            logger.error('Message preview:', preview)
            if (data instanceof Buffer) {
              logger.error('Binary data size:', data.length, 'bytes')
            }
        }
      })

      ws.on('close', () => {
        logger.info('Audio source disconnected')
        this.clients.delete(ws)
      })

      ws.on('error', (error) => {
        logger.error('WebSocket error:', error)
      })

      // Send initial status
      this.sendStatus(ws)
    })
  }

  private handleAudioData(message: AudioDataMessage) {
    // Decode base64 data
    const audioBuffer = Buffer.from(message.data, 'base64')

    // Process audio chunk
    this.processor.processChunk({
      timestamp: message.timestamp,
      format: message.format,
      data: audioBuffer,
      sourceId: message.sourceId
    })

    // Emit for other services to consume
    eventEmitter.emit('audio:chunk', {
      timestamp: message.timestamp,
      sourceId: message.sourceId,
      sourceName: message.sourceName,
      size: audioBuffer.byteLength
    })
  }

  private handleControlMessage(message: ControlMessage) {
    switch (message.type) {
      case 'start':
        logger.info('Audio streaming started')
        this.processor.start()
        eventEmitter.emit('audio:started')
        break

      case 'stop':
        logger.info('Audio streaming stopped')
        this.processor.stop()
        eventEmitter.emit('audio:stopped')
        break

      case 'heartbeat':
        // Keep connection alive
        break
    }
  }

  private sendStatus(ws: WSWebSocket) {
    const status = {
      type: 'status',
      connected: true,
      receiving: this.processor.isReceiving(),
      bufferSize: this.processor.getBufferSize(),
      transcribing: this.processor.isTranscribing()
    }

    ws.send(JSON.stringify(status))
  }

  public broadcastStatus() {
    for (const client of this.clients) {
      if (client.readyState === WSWebSocket.OPEN) {
        this.sendStatus(client)
      }
    }
  }

  public stop() {
    logger.info('Stopping phononmaser...')
    this.processor.stop()
    if (this.lmStudioService) {
      this.lmStudioService.stop()
    }
    this.wss.close()
  }
}

// Start the service
const receiver = new Phononmaser()

// Health check endpoint
const healthServer = Bun.serve({
  port: PORT + 1,
  fetch(_request) {
    return new Response(
      JSON.stringify({
        status: 'healthy',
        service: 'phononmaser',
        timestamp: Date.now()
      }),
      {
        headers: { 'Content-Type': 'application/json' }
      }
    )
  }
})

logger.info(`Health check available at http://localhost:${(PORT + 1).toString()}`)

// Graceful shutdown
process.on('SIGINT', () => {
  logger.info('Shutting down phononmaser...')
  receiver.stop()
  void healthServer.stop()
  process.exit(0)
})
