import type { LayerPriority } from '../hooks/use-layer-orchestrator'

export type ShowType = 'ironmon' | 'variety' | 'coding'
export type ContentType = string

// Layer priority mappings for different shows
export interface ShowLayerConfig {
  [contentType: string]: LayerPriority
}

export const SHOW_LAYER_MAPPINGS: Record<ShowType, ShowLayerConfig> = {
  ironmon: {
    // Foreground - Critical interrupts
    'death_alert': 'foreground',
    'elite_four_alert': 'foreground',
    'shiny_encounter': 'foreground',
    'alert': 'foreground',
    
    // Midground - Celebrations and notifications
    'level_up': 'midground',
    'gym_badge': 'midground',
    'sub_train': 'midground',
    'cheer_celebration': 'midground',
    
    // Background - Stats and ambient info
    'ironmon_run_stats': 'background',
    'ironmon_deaths': 'background',
    'recent_follows': 'background',
    'emote_stats': 'background'
  },
  
  variety: {
    // Foreground - Breaking alerts
    'raid_alert': 'foreground',
    'host_alert': 'foreground',
    'alert': 'foreground',
    
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
    'build_failure': 'foreground',
    'deployment_alert': 'foreground',
    'alert': 'foreground',
    
    // Midground - Development celebrations
    'commit_celebration': 'midground',
    'pr_merged': 'midground',
    'sub_train': 'midground',
    
    // Background - Development stats
    'commit_stats': 'background',
    'build_status': 'background',
    'recent_follows': 'background',
    'emote_stats': 'background'
  }
}

// Default layer mapping for unknown content types
export const DEFAULT_LAYER_MAPPING: ShowLayerConfig = {
  'alert': 'foreground',
  'sub_train': 'midground',
  'emote_stats': 'background',
  'recent_follows': 'background',
  'daily_stats': 'background'
}

// Get layer priority for content type and show
export function getLayerForContent(contentType: ContentType, show: ShowType): LayerPriority {
  const showMapping = SHOW_LAYER_MAPPINGS[show] || DEFAULT_LAYER_MAPPING
  return showMapping[contentType] || 'background'
}

// Get all content types for a specific layer and show
export function getContentTypesForLayer(layer: LayerPriority, show: ShowType): ContentType[] {
  const showMapping = SHOW_LAYER_MAPPINGS[show] || DEFAULT_LAYER_MAPPING
  
  return Object.entries(showMapping)
    .filter(([_, layerPriority]) => layerPriority === layer)
    .map(([contentType, _]) => contentType)
}

// Check if content type should be displayed on specific layer for show
export function shouldDisplayOnLayer(contentType: ContentType, layer: LayerPriority, show: ShowType): boolean {
  return getLayerForContent(contentType, show) === layer
}