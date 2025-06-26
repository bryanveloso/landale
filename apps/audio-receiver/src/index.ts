import { WebSocketServer, WebSocket as WSWebSocket } from 'ws'
import { logger } from './logger'
import { AudioProcessor } from './audio-processor'
import { eventEmitter } from './events'
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
const PORT = process.env.AUDIO_RECEIVER_PORT ? parseInt(process.env.AUDIO_RECEIVER_PORT) : 8889

export class AudioReceiver {
  private wss: WebSocketServer
  private processor: AudioProcessor
  private clients = new Set<WSWebSocket>()

  constructor() {
    this.processor = new AudioProcessor()
    this.wss = new WebSocketServer({ port: PORT })
    this.setupWebSocket()
    logger.info(`Audio receiver started on port ${PORT}`)
  }

  private setupWebSocket() {
    this.wss.on('connection', (ws) => {
      logger.info('New audio source connected')
      this.clients.add(ws)

      ws.on('message', async (data) => {
        try {
          // Check if it's binary data
          if (data instanceof Buffer) {
            // Handle raw binary audio data
            const timestamp = Date.now() * 1000 // microseconds
            
            // Auto-start processor if not running
            if (!this.processor.isReceiving()) {
              logger.info('Auto-starting audio processor')
              this.processor.start()
            }
            
            // Process the audio chunk
            await this.processor.processChunk({
              timestamp,
              format: {
                sampleRate: 48000, // Standard OBS sample rate
                channels: 2,       // Stereo
                bitDepth: 16       // 16-bit PCM
              },
              data: data,
              sourceId: 'obs_audio'
            })
            
            // Emit event for monitoring
            eventEmitter.emit('audio:chunk', {
              timestamp,
              sourceId: 'obs_audio',
              sourceName: 'OBS Audio Stream',
              size: data.length
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
}

// Start the service
const receiver = new AudioReceiver()

// Health check endpoint
const healthServer = Bun.serve({
  port: PORT + 1,
  fetch(request) {
    return new Response(JSON.stringify({
      status: 'healthy',
      service: 'audio-receiver',
      timestamp: Date.now()
    }), {
      headers: { 'Content-Type': 'application/json' }
    })
  }
})

logger.info(`Health check available at http://localhost:${PORT + 1}`)

// Graceful shutdown
process.on('SIGINT', () => {
  logger.info('Shutting down audio receiver...')
  healthServer.stop()
  process.exit(0)
})