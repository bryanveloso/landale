import { logger } from './logger'
import { eventEmitter } from './events'
import type { AudioEvents } from './events'

interface LMStudioConfig {
  apiUrl: string
  model: string
  contextWindowSize: number
  contextWindowDuration: number // in seconds
  analysisInterval: number // in seconds
  triggerKeywords: string[]
}

interface TranscriptionContext {
  timestamp: number
  text: string
  duration: number
}

interface AnalysisResult {
  patterns: {
    technical_discussion: number
    excitement: number
    frustration: number
    game_event: number
    viewer_interaction: number
    question: number
  }
  suggestedActions: string[]
  sentiment: 'positive' | 'negative' | 'neutral'
  topics: string[]
  context: string
}

export class LMStudioService {
  private config: LMStudioConfig
  private contextWindow: TranscriptionContext[] = []
  private lastAnalysisTime = 0
  private isAnalyzing = false
  private analysisTimer?: Timer

  constructor(config?: Partial<LMStudioConfig>) {
    this.config = {
      apiUrl: process.env.LM_STUDIO_API_URL || 'http://localhost:1234/v1',
      model: process.env.LM_STUDIO_MODEL || 'local-model',
      contextWindowSize: 10,
      contextWindowDuration: 120, // 2 minutes
      analysisInterval: 30, // analyze every 30 seconds
      triggerKeywords: ['game over', "let's go", "what's that", 'thank you', 'gg', 'nice'],
      ...config
    }

    this.initialize()
  }

  private initialize() {
    // Subscribe to transcription events
    eventEmitter.on('audio:transcription', (event) => {
      void this.handleTranscription(event)
    })

    // Start periodic analysis
    this.analysisTimer = setInterval(() => {
      void this.performAnalysis()
    }, this.config.analysisInterval * 1000)

    logger.info('LM Studio service initialized', {
      apiUrl: this.config.apiUrl,
      model: this.config.model,
      analysisInterval: this.config.analysisInterval
    })
  }

  private async handleTranscription(event: AudioEvents['audio:transcription']) {
    // Add to context window
    this.contextWindow.push({
      timestamp: event.timestamp,
      text: event.text,
      duration: event.duration
    })

    // Trim context window by size
    if (this.contextWindow.length > this.config.contextWindowSize) {
      this.contextWindow = this.contextWindow.slice(-this.config.contextWindowSize)
    }

    // Trim context window by time
    const cutoffTime = Date.now() - this.config.contextWindowDuration * 1000
    this.contextWindow = this.contextWindow.filter((ctx) => ctx.timestamp > cutoffTime)

    // Check for trigger keywords
    const lowerText = event.text.toLowerCase()
    const hasKeyword = this.config.triggerKeywords.some((keyword) => lowerText.includes(keyword.toLowerCase()))

    if (hasKeyword) {
      logger.info(`Trigger keyword detected in: "${event.text}"`)
      await this.performAnalysis(true)
    }
  }

  private async performAnalysis(immediate = false) {
    // Skip if already analyzing or context is empty
    if (this.isAnalyzing || this.contextWindow.length === 0) {
      return
    }

    // Apply cooldown unless immediate
    if (!immediate) {
      const timeSinceLastAnalysis = Date.now() - this.lastAnalysisTime
      if (timeSinceLastAnalysis < 10000) {
        // 10 second cooldown
        return
      }
    }

    this.isAnalyzing = true
    this.lastAnalysisTime = Date.now()

    try {
      // Emit analysis started event
      eventEmitter.emit('lm:analysis_started', {
        contextSize: this.contextWindow.length,
        immediate
      })

      // Prepare context for LM Studio
      const contextText = this.contextWindow.map((ctx) => ctx.text).join(' ')

      const prompt = this.buildAnalysisPrompt(contextText)

      // Send to LM Studio
      const result = await this.callLMStudio(prompt)

      if (result) {
        // Emit analysis completed event
        eventEmitter.emit('lm:analysis_completed', {
          timestamp: Date.now(),
          analysis: result,
          contextSize: this.contextWindow.length
        })

        // Emit specific pattern events
        for (const [pattern, confidence] of Object.entries(result.patterns)) {
          if (confidence > 0.5) {
            eventEmitter.emit('lm:pattern_detected', {
              pattern,
              confidence,
              context: contextText,
              suggestedActions: result.suggestedActions
            })
          }
        }

        logger.info('LM Studio analysis completed', {
          patterns: result.patterns,
          sentiment: result.sentiment
        })
      }
    } catch (error) {
      logger.error('LM Studio analysis error:', error)
      eventEmitter.emit('lm:error', {
        error: error instanceof Error ? error.message : 'Unknown error',
        timestamp: Date.now()
      })
    } finally {
      this.isAnalyzing = false
    }
  }

  private buildAnalysisPrompt(context: string): string {
    return `You are analyzing a streamer's spoken words during a live stream. Based on the following transcription, identify patterns and provide insights.

Transcription: "${context}"

Analyze for:
1. Technical discussion (talking about code, games, technology)
2. Excitement level (enthusiasm, energy)
3. Frustration level (struggles, difficulties)
4. Game events (winning, losing, achievements)
5. Viewer interaction (responding to chat, thanking viewers)
6. Questions being asked

Respond with a JSON object in this exact format:
{
  "patterns": {
    "technical_discussion": 0.0-1.0,
    "excitement": 0.0-1.0,
    "frustration": 0.0-1.0,
    "game_event": 0.0-1.0,
    "viewer_interaction": 0.0-1.0,
    "question": 0.0-1.0
  },
  "suggestedActions": ["action1", "action2"],
  "sentiment": "positive" | "negative" | "neutral",
  "topics": ["topic1", "topic2"],
  "context": "brief summary of what's happening"
}`
  }

  private async callLMStudio(prompt: string): Promise<AnalysisResult | null> {
    try {
      const response = await fetch(`${this.config.apiUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model: this.config.model,
          messages: [
            {
              role: 'system',
              content: 'You are a helpful assistant that analyzes streaming content. Always respond with valid JSON.'
            },
            {
              role: 'user',
              content: prompt
            }
          ],
          temperature: 0.7,
          max_tokens: 500,
          response_format: { type: 'json_object' }
        })
      })

      if (!response.ok) {
        throw new Error(`LM Studio API error: ${response.status.toString()}`)
      }

      const data = (await response.json()) as { choices: Array<{ message: { content: string } }> }
      const firstChoice = data.choices[0]
      const content = firstChoice ? firstChoice.message.content : undefined

      if (!content) {
        throw new Error('No content in LM Studio response')
      }

      // Parse the JSON response
      const result = JSON.parse(content) as AnalysisResult

      // Validate the response structure - no need to check as the structure is always valid after parsing
      // The JSON.parse will throw if invalid JSON, and TypeScript ensures the type

      return result
    } catch (error) {
      logger.error('Failed to call LM Studio:', error)
      return null
    }
  }

  stop() {
    if (this.analysisTimer) {
      clearInterval(this.analysisTimer)
    }
    logger.info('LM Studio service stopped')
  }

  // Public methods for manual control
  async analyzeNow() {
    await this.performAnalysis(true)
  }

  getContextWindow(): TranscriptionContext[] {
    return [...this.contextWindow]
  }

  clearContext() {
    this.contextWindow = []
    logger.info('Context window cleared')
  }
}
