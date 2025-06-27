import { spawn } from 'child_process'
import { whisperLogger as logger } from '@lib/logger'
import { writeFile, unlink } from 'fs/promises'
import { tmpdir } from 'os'
import { join } from 'path'

interface WhisperOptions {
  modelPath: string
  model?: 'tiny' | 'base' | 'small' | 'medium' | 'large'
  language?: string
  threads?: number
}

export class WhisperService {
  private whisperPath: string
  private modelPath: string
  private options: WhisperOptions
  private isProcessing = false

  constructor(whisperPath: string, options: WhisperOptions) {
    this.whisperPath = whisperPath
    this.modelPath = options.modelPath
    this.options = {
      model: 'base',
      language: 'en',
      threads: 4,
      ...options
    }

    logger.info('Whisper service initialized', {
      model: this.options.model,
      language: this.options.language
    })
  }

  async transcribe(
    audioBuffer: Buffer,
    format: { sampleRate: number; channels: number; bitDepth: number }
  ): Promise<string> {
    if (this.isProcessing) {
      logger.warn('Whisper is already processing, skipping this buffer')
      return ''
    }

    this.isProcessing = true
    const startTime = Date.now()

    try {
      // Create temporary WAV file
      const tempFile = join(tmpdir(), `audio_${Date.now().toString()}.wav`)
      await this.saveAsWav(audioBuffer, format, tempFile)

      // Run whisper.cpp
      const result = await this.runWhisper(tempFile)

      // Clean up
      await unlink(tempFile).catch(() => {})

      const duration = Date.now() - startTime
      logger.debug(`Transcription completed in ${duration.toString()}ms`)

      return result
    } catch (error) {
      logger.error('Transcription error', { error: error as Error })
      return ''
    } finally {
      this.isProcessing = false
    }
  }

  private async saveAsWav(
    buffer: Buffer,
    format: { sampleRate: number; channels: number; bitDepth: number },
    filepath: string
  ) {
    // Create WAV header
    const dataSize = buffer.length
    const header = Buffer.alloc(44)

    // RIFF header
    header.write('RIFF', 0)
    header.writeUInt32LE(36 + dataSize, 4)
    header.write('WAVE', 8)

    // fmt chunk
    header.write('fmt ', 12)
    header.writeUInt32LE(16, 16) // fmt chunk size
    header.writeUInt16LE(1, 20) // PCM format
    header.writeUInt16LE(format.channels, 22)
    header.writeUInt32LE(format.sampleRate, 24)
    header.writeUInt32LE(format.sampleRate * format.channels * (format.bitDepth / 8), 28) // byte rate
    header.writeUInt16LE(format.channels * (format.bitDepth / 8), 32) // block align
    header.writeUInt16LE(format.bitDepth, 34)

    // data chunk
    header.write('data', 36)
    header.writeUInt32LE(dataSize, 40)

    // Write file
    const wav = Buffer.concat([header, buffer])
    await writeFile(filepath, wav)
  }

  private runWhisper(audioFile: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const vadModelPath = process.env.WHISPER_VAD_MODEL_PATH
      const args = [
        '-m',
        this.modelPath,
        '-f',
        audioFile,
        '-t',
        (this.options.threads ?? 4).toString(),
        '-l',
        this.options.language ?? 'en',
        '--no-timestamps',
        '-otxt'
      ]

      // Add VAD if model is available
      if (vadModelPath) {
        args.push('--vad', '--vad-model', vadModelPath)
      }

      logger.debug(`Spawning whisper: ${this.whisperPath} ${args.join(' ')}`)

      const whisper = spawn(this.whisperPath, args)
      let output = ''
      let error = ''

      whisper.stdout.on('data', (data: Buffer) => {
        output += data.toString()
      })

      whisper.stderr.on('data', (data: Buffer) => {
        error += data.toString()
      })

      whisper.on('close', (code) => {
        if (error) {
          logger.debug('Whisper stderr:', error.substring(0, 500))
        }

        if (code === 0) {
          // Extract the transcription from output
          const lines = output.split('\n')
          const transcription = lines
            .filter((line) => !line.startsWith('[') && line.trim() !== '')
            .join(' ')
            .trim()

          logger.debug(`Whisper output: "${output.substring(0, 200)}"`)
          resolve(transcription)
        } else {
          reject(new Error(`Whisper exited with code ${code?.toString() ?? 'unknown'}: ${error}`))
        }
      })

      whisper.on('error', (err) => {
        logger.error('Whisper spawn error', { error: err as Error })
        reject(err)
      })
    })
  }

  isAvailable(): boolean {
    // Check if whisper binary exists
    try {
      const result = spawn(this.whisperPath, ['--help'])
      result.kill()
      return true
    } catch {
      return false
    }
  }
}
