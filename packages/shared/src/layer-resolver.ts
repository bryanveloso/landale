/**
 * Unified Layer Resolution Logic
 *
 * Centralizes the content→layer mapping logic that was previously duplicated
 * between dashboard stream-service and overlays layer-mappings.
 *
 * Handles priority-based content distribution across foreground, midground, 
 * and background layers for different show types (ironmon, variety, coding).
 */

export type LayerPriority = 'foreground' | 'midground' | 'background'
export type ShowType = 'ironmon' | 'variety' | 'coding'
export type ContentType = string

export interface StreamContent {
  type: ContentType
  priority: number
  data?: Record<string, unknown>
  id?: string
  started_at?: string
  duration?: number
}

export interface LayerState {
  priority: LayerPriority
  state: 'active' | 'hidden'
  content: StreamContent | null
}

export interface LayerDistribution {
  foreground: LayerState
  midground: LayerState  
  background: LayerState
}

export interface ShowLayerConfig {
  [contentType: string]: LayerPriority
}

// Centralized layer mappings for all show types
export const SHOW_LAYER_MAPPINGS: Record<ShowType, ShowLayerConfig> = {
  ironmon: {
    // Foreground - Critical interrupts
    'alert': 'foreground',
    'death_alert': 'foreground',
    'elite_four_alert': 'foreground', 
    'shiny_encounter': 'foreground',
    
    // Midground - Celebrations and notifications
    'sub_train': 'midground',
    'level_up': 'midground',
    'gym_badge': 'midground',
    'cheer_celebration': 'midground',
    
    // Background - Stats and ambient info
    'ironmon_run_stats': 'background',
    'ironmon_deaths': 'background',
    'recent_follows': 'background',
    'emote_stats': 'background'
  },
  
  variety: {
    // Foreground - Breaking alerts
    'alert': 'foreground',
    'raid_alert': 'foreground',
    'host_alert': 'foreground',
    
    // Midground - Community interactions
    'sub_train': 'midground',
    'cheer_celebration': 'midground',
    'follow_celebration': 'midground',
    
    // Background - Community stats
    'emote_stats': 'background',
    'recent_follows': 'background',
    'stream_goals': 'background',
    'daily_stats': 'background'
  },
  
  coding: {
    // Foreground - Critical development alerts
    'alert': 'foreground',
    'build_failure': 'foreground',
    'deployment_alert': 'foreground',
    
    // Midground - Development celebrations
    'sub_train': 'midground',
    'commit_celebration': 'midground',
    'pr_merged': 'midground',
    
    // Background - Development stats
    'commit_stats': 'background',
    'build_status': 'background',
    'recent_follows': 'background',
    'emote_stats': 'background'
  }
}

// Default fallback mapping for unknown show types
export const DEFAULT_LAYER_MAPPING: ShowLayerConfig = {
  'alert': 'foreground',
  'sub_train': 'midground', 
  'emote_stats': 'background',
  'recent_follows': 'background',
  'daily_stats': 'background'
}

// Performance optimization: Cache mapping lookups
const _mappingCache = new Map<string, LayerPriority>()
const MAX_CACHE_SIZE = 100

// Import performance monitor
import { PerformanceMonitor } from './performance'

/**
 * Layer Resolution Functions
 */
export class LayerResolver {
  /**
   * Get the appropriate layer for a content type and show
   * Uses caching for performance optimization
   */
  static getLayerForContent(contentType: ContentType, show: ShowType): LayerPriority {
    const cacheKey = `${show}:${contentType}`
    
    // Check cache first
    if (_mappingCache.has(cacheKey)) {
      return _mappingCache.get(cacheKey)!
    }
    
    // Calculate and cache result
    const showMapping = SHOW_LAYER_MAPPINGS[show] || DEFAULT_LAYER_MAPPING
    const result = showMapping[contentType] || 'background'
    
    // Manage cache size
    if (_mappingCache.size >= MAX_CACHE_SIZE) {
      const firstKey = _mappingCache.keys().next().value
      if (firstKey !== undefined) {
        _mappingCache.delete(firstKey)
      }
    }
    
    _mappingCache.set(cacheKey, result)
    
    return result
  }

  /**
   * Check if content should display on a specific layer for a show
   */
  static shouldDisplayOnLayer(contentType: ContentType, layer: LayerPriority, show: ShowType): boolean {
    return this.getLayerForContent(contentType, show) === layer
  }

  /**
   * Get the highest priority content for a specific layer
   * Optimized to avoid unnecessary sorting
   */
  static getContentForLayer(
    allContent: StreamContent[],
    targetLayer: LayerPriority,
    show: ShowType
  ): StreamContent | null {
    if (!allContent || allContent.length === 0) return null

    let highestPriorityContent: StreamContent | null = null
    let highestPriority = -1

    // Single pass to find highest priority content for this layer
    for (const content of allContent) {
      if (!content || !content.type) continue
      
      if (this.shouldDisplayOnLayer(content.type, targetLayer, show)) {
        const priority = content.priority || 0
        if (priority > highestPriority) {
          highestPriority = priority
          highestPriorityContent = content
        }
      }
    }

    return highestPriorityContent
  }

  /**
   * Distribute all content across layers based on show type
   * Returns complete layer distribution for overlay rendering
   */
  static distributeContent(allContent: StreamContent[], show: ShowType): LayerDistribution {
    return PerformanceMonitor.trackLayerResolution(() => {
      const foregroundContent = this.getContentForLayer(allContent, 'foreground', show)
      const midgroundContent = this.getContentForLayer(allContent, 'midground', show)
      const backgroundContent = this.getContentForLayer(allContent, 'background', show)

      return {
        foreground: {
          priority: 'foreground',
          state: foregroundContent ? 'active' : 'hidden',
          content: foregroundContent
        },
        midground: {
          priority: 'midground',
          state: midgroundContent ? 'active' : 'hidden', 
          content: midgroundContent
        },
        background: {
          priority: 'background',
          state: backgroundContent ? 'active' : 'hidden',
          content: backgroundContent
        }
      }
    })
  }

  /**
   * Get all content types that should display on a specific layer for a show
   */
  static getContentTypesForLayer(layer: LayerPriority, show: ShowType): ContentType[] {
    const showMapping = SHOW_LAYER_MAPPINGS[show] || DEFAULT_LAYER_MAPPING
    
    return Object.entries(showMapping)
      .filter(([_, layerPriority]) => layerPriority === layer)
      .map(([contentType, _]) => contentType)
  }

  /**
   * Cache management utilities for development and testing
   */
  static clearCache(): void {
    _mappingCache.clear()
  }

  static getCacheSize(): number {
    return _mappingCache.size
  }
}