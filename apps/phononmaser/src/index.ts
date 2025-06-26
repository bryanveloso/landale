import 'dotenv/config'
import { WebSocketServer, WebSocket as WSWebSocket } from 'ws'
import { logger } from './logger'
import { AudioProcessor } from './audio-processor'
import { eventEmitter } from './events'
import { LMStudioService } from './lm-studio-service'
import { z } from 'zod'

// Message schemas
const AudioDataMessageSchema = z.object({
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

const ControlMessageSchema = z.object({
  type: z.enum(['start', 'stop', 'heartbeat']),
  timestamp: z.number()
})

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
    logger.info(`Phononmaser started on port ${PORT}`)
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

      ws.on('message', async (data) => {
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
            const timestamp = data.readBigUInt64LE(offset); offset += 8
            const sampleRate = data.readUInt32LE(offset); offset += 4
            const channels = data.readUInt32LE(offset); offset += 4
            const bitDepth = data.readUInt32LE(offset); offset += 4
            const sourceIdLen = data.readUInt32LE(offset); offset += 4
            const sourceNameLen = data.readUInt32LE(offset); offset += 4
            
            // Only log header once per connection
            if (!this.headerLogged) {
              logger.debug(`Header: timestamp=${timestamp}, rate=${sampleRate}, ch=${channels}, sourceIdLen=${sourceIdLen}, sourceNameLen=${sourceNameLen}`)
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
              logger.debug(`Audio packet: ${sampleRate}Hz, ${channels}ch, ${bitDepth}bit, ${audioData.length} bytes from ${sourceName}`)
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
            await this.processor.processChunk({
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
          const message = JSON.parse(data.toString())
          
          if (message.type === 'audio_data') {
            await this.handleAudioData(message)
          } else if (['start', 'stop', 'heartbeat'].includes(message.type)) {
            await this.handleControlMessage(message)
          }
        } catch (error) {
          logger.error('Error processing message:', error)
          logger.error('Message type:', typeof data)
          logger.error('Message preview:', data.toString().substring(0, 200))
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

  private async handleAudioData(message: z.infer<typeof AudioDataMessageSchema>) {
    // Decode base64 data
    const audioBuffer = Buffer.from(message.data, 'base64')
    
    // Process audio chunk
    await this.processor.processChunk({
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

  private async handleControlMessage(message: z.infer<typeof ControlMessageSchema>) {
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

  public async stop() {
    logger.info('Stopping phononmaser...')
    this.processor.stop()
    if (this.lmStudioService) {
      await this.lmStudioService.stop()
    }
    this.wss.close()
  }
}

// Start the service
const receiver = new Phononmaser()

// Health check endpoint
const healthServer = Bun.serve({
  port: PORT + 1,
  fetch(request) {
    return new Response(JSON.stringify({
      status: 'healthy',
      service: 'phononmaser',
      timestamp: Date.now()
    }), {
      headers: { 'Content-Type': 'application/json' }
    })
  }
})

logger.info(`Health check available at http://localhost:${PORT + 1}`)

// Graceful shutdown
process.on('SIGINT', async () => {
  logger.info('Shutting down phononmaser...')
  await receiver.stop()
  healthServer.stop()
  process.exit(0)
})