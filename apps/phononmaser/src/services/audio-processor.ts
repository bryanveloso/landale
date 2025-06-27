import { audioLogger as logger } from '@lib/logger'
import { eventEmitter } from '@events'
import { WhisperService } from '@services/whisper-service'

interface AudioChunk {
  timestamp: number
  format: {
    sampleRate: number
    channels: number
    bitDepth: number
  }
  data: Buffer
  sourceId: string
}

interface AudioBuffer {
  chunks: AudioChunk[]
  startTimestamp: number
  endTimestamp: number
  totalSize: number
}

export class AudioProcessor {
  private buffer: AudioBuffer = {
    chunks: [],
    startTimestamp: 0,
    endTimestamp: 0,
    totalSize: 0
  }

  private isRunning = false
  private transcribing = false
  private readonly BUFFER_DURATION_MS = 1500 // 1.5 seconds for lower latency
  private readonly MAX_BUFFER_SIZE = 10 * 1024 * 1024 // 10MB max
  private processTimer?: Timer
  private whisperService?: WhisperService
  private lastLoggedDuration = 0

  constructor() {
    this.initializeWhisper()
  }

  private initializeWhisper() {
    try {
      // Check if whisper is configured
      const whisperPath = process.env.WHISPER_CPP_PATH
      const modelPath = process.env.WHISPER_MODEL_PATH

      if (!whisperPath || !modelPath) {
        logger.warn('Whisper not configured in environment variables')
        return
      }

      this.whisperService = new WhisperService(whisperPath, {
        modelPath,
        model: 'large', // Using large-v3-turbo
        language: 'en',
        threads: 8 // Use more threads on Mac Studio
      })

      if (this.whisperService.isAvailable()) {
        logger.info('Whisper transcription service initialized')
      } else {
        logger.warn('Whisper binary not found, transcription disabled')
        this.whisperService = undefined
      }
    } catch (error) {
      logger.error('Failed to initialize Whisper', { error: error as Error })
    }
  }

  start() {
    this.isRunning = true
    this.startProcessingLoop()
  }

  stop() {
    this.isRunning = false
    if (this.processTimer) {
      clearInterval(this.processTimer)
    }
  }

  processChunk(chunk: AudioChunk) {
    if (!this.isRunning) {
      logger.warn('Audio processor not running, dropping chunk')
      return
    }

    // Initialize buffer timestamp if empty
    if (this.buffer.chunks.length === 0) {
      this.buffer.startTimestamp = chunk.timestamp
      logger.debug('Starting new audio buffer')
    }

    // Add chunk to buffer
    this.buffer.chunks.push(chunk)
    this.buffer.endTimestamp = chunk.timestamp
    this.buffer.totalSize += chunk.data.length

    // Prevent buffer overflow
    if (this.buffer.totalSize > this.MAX_BUFFER_SIZE) {
      logger.warn('Audio buffer overflow, dropping oldest chunks')
      while (this.buffer.totalSize > this.MAX_BUFFER_SIZE && this.buffer.chunks.length > 0) {
        const removed = this.buffer.chunks.shift()
        if (removed) {
          this.buffer.totalSize -= removed.data.length
        }
      }
    }

    // Log buffer status at meaningful intervals (every second of audio)
    const duration = this.getBufferDuration()
    const lastLoggedSecond = Math.floor(this.lastLoggedDuration || 0)
    const currentSecond = Math.floor(duration)

    if (currentSecond > lastLoggedSecond) {
      logger.debug(`Buffer: ${duration.toFixed(1)}s of audio (${(this.buffer.totalSize / 1024 / 1024).toFixed(1)}MB)`)
      this.lastLoggedDuration = duration
    }
  }

  private startProcessingLoop() {
    // Process buffer at the configured interval
    this.processTimer = setInterval(() => {
      if (this.shouldProcessBuffer()) {
        void this.processBuffer()
      }
    }, this.BUFFER_DURATION_MS)
  }

  private shouldProcessBuffer(): boolean {
    if (this.buffer.chunks.length === 0) return false
    if (this.transcribing) return false

    const duration = this.buffer.endTimestamp - this.buffer.startTimestamp
    return duration >= this.BUFFER_DURATION_MS * 1000 // Convert to microseconds
  }

  private async processBuffer() {
    if (this.buffer.chunks.length === 0) return

    this.transcribing = true
    const processingBuffer = { ...this.buffer }

    // Reset buffer for new chunks
    this.buffer = {
      chunks: [],
      startTimestamp: 0,
      endTimestamp: 0,
      totalSize: 0
    }
    this.lastLoggedDuration = 0

    try {
      // Combine all chunks into single PCM buffer
      const pcmData = this.combineChunks(processingBuffer.chunks)

      const format = processingBuffer.chunks[0]?.format || { sampleRate: 48000, channels: 2, bitDepth: 16 }

      // Emit buffer ready event
      eventEmitter.emit('audio:buffer_ready', {
        startTimestamp: processingBuffer.startTimestamp,
        endTimestamp: processingBuffer.endTimestamp,
        duration: (processingBuffer.endTimestamp - processingBuffer.startTimestamp) / 1000000, // Convert to seconds
        format,
        pcmData,
        size: pcmData.length
      })

      const durationSeconds = (processingBuffer.endTimestamp - processingBuffer.startTimestamp) / 1000000
      logger.debug(
        `Processing ${durationSeconds.toFixed(1)}s of audio (${format.sampleRate.toString()}Hz, ${format.channels.toString()}ch, ${format.bitDepth.toString()}bit)...`
      )

      // Transcribe if Whisper is available
      if (this.whisperService) {
        const transcription = await this.whisperService.transcribe(pcmData, format)

        if (transcription) {
          eventEmitter.emit('audio:transcription', {
            timestamp: processingBuffer.startTimestamp,
            duration: durationSeconds,
            text: transcription
          })

          logger.info(`Transcription: "${transcription}"`)
        } else {
          logger.trace('No speech detected in buffer')
        }
      }
    } catch (error) {
      logger.error('Error processing audio buffer', { error: error as Error })
    } finally {
      this.transcribing = false
    }
  }

  private combineChunks(chunks: AudioChunk[]): Buffer {
    const totalSize = chunks.reduce((sum, chunk) => sum + chunk.data.length, 0)
    const combined = Buffer.allocUnsafe(totalSize)

    let offset = 0
    for (const chunk of chunks) {
      chunk.data.copy(combined, offset)
      offset += chunk.data.length
    }

    return combined
  }

  isReceiving(): boolean {
    return this.isRunning
  }

  isTranscribing(): boolean {
    return this.transcribing
  }

  getBufferSize(): number {
    return this.buffer.totalSize
  }

  getBufferDuration(): number {
    if (this.buffer.chunks.length === 0) return 0
    return (this.buffer.endTimestamp - this.buffer.startTimestamp) / 1000000 // Convert to seconds
  }
}
