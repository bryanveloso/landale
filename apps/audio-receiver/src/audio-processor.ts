import { logger } from './logger'
import { eventEmitter } from './events'

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
  private readonly BUFFER_DURATION_MS = 3000 // 3 seconds of audio
  private readonly MAX_BUFFER_SIZE = 10 * 1024 * 1024 // 10MB max
  private processTimer?: Timer

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

  async processChunk(chunk: AudioChunk) {
    if (!this.isRunning) return

    // Initialize buffer timestamp if empty
    if (this.buffer.chunks.length === 0) {
      this.buffer.startTimestamp = chunk.timestamp
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

    // Only log every 10th chunk to reduce spam
    if (this.buffer.chunks.length % 10 === 0) {
      logger.info(`Buffer: ${this.buffer.chunks.length} chunks, ${(this.buffer.totalSize / 1024).toFixed(1)}KB, ${(this.getBufferDuration()).toFixed(1)}s`)
    }
  }

  private startProcessingLoop() {
    // Process buffer every 3 seconds
    this.processTimer = setInterval(async () => {
      if (this.shouldProcessBuffer()) {
        await this.processBuffer()
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

    try {
      // Combine all chunks into single PCM buffer
      const pcmData = this.combineChunks(processingBuffer.chunks)
      
      // TODO: Send to Whisper for transcription
      // For now, emit the raw audio data
      eventEmitter.emit('audio:buffer_ready', {
        startTimestamp: processingBuffer.startTimestamp,
        endTimestamp: processingBuffer.endTimestamp,
        duration: (processingBuffer.endTimestamp - processingBuffer.startTimestamp) / 1000000, // Convert to seconds
        format: processingBuffer.chunks[0]?.format || { sampleRate: 48000, channels: 2, bitDepth: 16 },
        pcmData,
        size: pcmData.length
      })

      logger.info(`Audio buffer ready for transcription: ${pcmData.length} bytes, ${processingBuffer.chunks.length} chunks`)
    } catch (error) {
      logger.error('Error processing audio buffer:', error)
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