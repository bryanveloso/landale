import { lmLogger as logger } from '@lib/logger'
import { eventEmitter } from '@events'
import type { AudioEvents } from '@events'
import { avalonstarEmoteRepository, type EmoteAnalysis } from '@landale/shared'

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
      apiUrl: process.env.LM_STUDIO_API_URL || 'http://zelan:1234/v1',
      model: process.env.LM_STUDIO_MODEL || 'dolphin-2.9.3-llama-3-8b',
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
      metadata: {
        apiUrl: this.config.apiUrl,
        model: this.config.model,
        analysisInterval: this.config.analysisInterval
      }
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

        // Run emote analysis in parallel
        void this.analyzeForEmotes(contextText)

        logger.info('LM Studio analysis completed', {
          metadata: {
            patterns: result.patterns,
            sentiment: result.sentiment
          }
        })
      }
    } catch (error) {
      logger.error('LM Studio analysis error', { error: error as Error })
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

  private buildEmoteAnalysisPrompt(context: string): string {
    return `You are analyzing a streamer's spoken words to suggest appropriate emotes for their Twitch channel.

Transcription: "${context}"

Analyze the emotional content and suggest emotes. Consider:
- Overall emotion (excited, frustrated, confused, happy, sad, neutral, hype, thinking)
- Intensity level (1-10 scale)
- Context and meaning

Respond with a JSON object in this exact format:
{
  "emotion": "excited" | "frustrated" | "confused" | "happy" | "sad" | "neutral" | "hype" | "thinking",
  "intensity": 1-10,
  "triggers": ["suggested_emote_names"],
  "shouldTrigger": true/false,
  "confidence": 0.0-1.0,
  "context": "brief explanation of why these emotes fit"
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
          max_tokens: 500
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

      return result
    } catch (error) {
      logger.error('Failed to call LM Studio', { error: error as Error })
      return null
    }
  }

  private async analyzeForEmotes(context: string): Promise<void> {
    try {
      const prompt = this.buildEmoteAnalysisPrompt(context)
      
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
              content: 'You are analyzing streaming content for emote suggestions. Always respond with valid JSON.'
            },
            {
              role: 'user',
              content: prompt
            }
          ],
          temperature: 0.7,
          max_tokens: 300
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

      const emoteAnalysis = JSON.parse(content) as EmoteAnalysis

      if (emoteAnalysis.shouldTrigger && emoteAnalysis.confidence > 0.6) {
        // Get emotes based on AI's emotion/intensity analysis
        const aiSuggestedEmotes = avalonstarEmoteRepository.selectEmotesForEmotion(
          emoteAnalysis.emotion, 
          emoteAnalysis.intensity
        )

        // Also check for keyword matches in the transcription
        const keywordMatches = avalonstarEmoteRepository.matchEmotesToText(context)
        const keywordEmotes = keywordMatches.map(match => match.name)

        // Combine and deduplicate
        const allSuggestedEmotes = [...new Set([...aiSuggestedEmotes, ...keywordEmotes])]
        
        // Filter to only include available emotes
        const availableEmotes = avalonstarEmoteRepository.filterAvailableEmotes(allSuggestedEmotes)

        // Log the emote analysis
        logger.info('🎭 Emote analysis completed', {
          metadata: {
            emotion: emoteAnalysis.emotion,
            intensity: emoteAnalysis.intensity,
            confidence: emoteAnalysis.confidence,
            context: emoteAnalysis.context,
            aiSuggested: aiSuggestedEmotes.slice(0, 3),
            keywordMatched: keywordEmotes.slice(0, 3),
            finalSelection: availableEmotes.slice(0, 5),
            transcription: context.slice(0, 100) + (context.length > 100 ? '...' : '')
          }
        })

        // Emit emote suggestion event
        eventEmitter.emit('lm:emote_suggestion', {
          timestamp: Date.now(),
          analysis: emoteAnalysis,
          suggestedEmotes: availableEmotes,
          aiEmotes: aiSuggestedEmotes,
          keywordEmotes: keywordEmotes,
          transcription: context
        })
      }
    } catch (error) {
      logger.error('Failed to analyze for emotes', { error: error as Error })
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
