// Example of how to consume LM Studio events in other services
import { eventEmitter } from './events'
import { logger } from './logger'

// Example: WebSocket service to forward events to overlays
export class LMStudioEventForwarder {
  constructor(private wsClients: Set<WebSocket>) {
    this.setupEventListeners()
  }

  private setupEventListeners() {
    // Listen for analysis completions
    eventEmitter.on('lm:analysis_completed', (event) => {
      this.broadcast({
        type: 'ai_analysis',
        timestamp: event.timestamp,
        sentiment: event.analysis.sentiment,
        patterns: event.analysis.patterns,
        topics: event.analysis.topics
      })
    })

    // Listen for pattern detections
    eventEmitter.on('lm:pattern_detected', (event) => {
      // High confidence patterns trigger immediate actions
      if (event.confidence > 0.8) {
        this.broadcast({
          type: 'pattern_trigger',
          pattern: event.pattern,
          confidence: event.confidence,
          actions: event.suggestedActions
        })

        // Example: Trigger emote rain on high excitement
        if (event.pattern === 'excitement' && event.confidence > 0.9) {
          this.triggerEmoteRain('hype')
        }

        // Example: Show support message on viewer interaction
        if (event.pattern === 'viewer_interaction') {
          this.showSupportMessage()
        }
      }
    })

    // Monitor errors
    eventEmitter.on('lm:error', (event) => {
      logger.error('LM Studio error:', event.error)
    })
  }

  private broadcast(data: any) {
    const message = JSON.stringify(data)
    for (const client of this.wsClients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(message)
      }
    }
  }

  private triggerEmoteRain(type: string) {
    this.broadcast({
      type: 'emote_rain',
      emoteType: type,
      duration: 5000
    })
  }

  private showSupportMessage() {
    this.broadcast({
      type: 'show_message',
      message: 'Thanks for the support!',
      duration: 3000
    })
  }
}

// Example: Database service to store insights
export class LMStudioInsightStorage {
  constructor() {
    this.setupEventListeners()
  }

  private setupEventListeners() {
    eventEmitter.on('lm:analysis_completed', async (event) => {
      // Store analysis for historical tracking
      await this.storeAnalysis({
        timestamp: event.timestamp,
        sentiment: event.analysis.sentiment,
        patterns: event.analysis.patterns,
        topics: event.analysis.topics,
        context: event.analysis.context
      })
    })

    eventEmitter.on('lm:pattern_detected', async (event) => {
      // Track pattern occurrences
      await this.incrementPatternCount(event.pattern, event.confidence)
    })
  }

  private async storeAnalysis(data: any) {
    // Database storage logic here
    logger.info('Storing AI analysis', { sentiment: data.sentiment })
  }

  private async incrementPatternCount(pattern: string, confidence: number) {
    // Pattern tracking logic here
    logger.info('Pattern detected', { pattern, confidence })
  }
}

// Example: Integration with existing services
export function integrateWithExistingServices() {
  // Listen for transcriptions to add game context
  eventEmitter.on('audio:transcription', (event) => {
    // Could check for game-specific terms here
    const gameTerms = ['pokemon', 'battle', 'catch', 'trainer']
    const hasGameContext = gameTerms.some((term) => event.text.toLowerCase().includes(term))

    if (hasGameContext) {
      logger.info('Game context detected in transcription')
    }
  })

  // Combine with other events for richer context
  eventEmitter.on('lm:analysis_completed', (event) => {
    // Could combine with Twitch chat events, game state, etc.
    if (event.analysis.patterns.game_event > 0.7) {
      // Check current game state and enhance the analysis
      logger.info('High game event confidence, checking game state...')
    }
  })
}
