import { z } from 'zod'

export const emoteRainConfigSchema = z.object({
  size: z.number().min(28).max(224).default(112),
  lifetime: z.number().min(1000).max(60000).default(30000),
  gravity: z.number().min(0.1).max(3).default(1),
  restitution: z.number().min(0).max(1).default(0.4),
  friction: z.number().min(0).max(1).default(0.3),
  airFriction: z.number().min(0).max(0.05).default(0.001),
  spawnDelay: z.number().min(50).max(1000).default(100),
  maxEmotes: z.number().min(10).max(500).default(200),
  rotationSpeed: z.number().min(0).max(1).default(0.2)
})

export type EmoteRainConfig = z.infer<typeof emoteRainConfigSchema>

export interface SystemStatus {
  status: 'online' | 'offline'
  timestamp: string
  uptime: {
    seconds: number
    formatted: string
  }
  memory: {
    rss: string
    heapTotal: string
    heapUsed: string
    external: string
  }
  version: string
}

export interface BrowserSource {
  id: string
  type: string
  connectedAt: string
  lastPing: string
}

export interface SourceEvent {
  type: 'control:source:connected' | 'control:source:disconnected' | 'control:source:ping'
  data: { id: string; type?: string }
}

export interface ActivityEvent {
  id: string
  type: string
  timestamp: string
  data: unknown
}

export const statusBarModeSchema = z.enum([
  'preshow',
  'soapbox',
  'game',
  'outro',
  'break',
  'custom'
])

export type StatusBarMode = z.infer<typeof statusBarModeSchema>

export const statusBarConfigSchema = z.object({
  mode: statusBarModeSchema,
  text: z.string().optional(),
  isVisible: z.boolean().default(true),
  position: z.enum(['top', 'bottom']).default('bottom')
})

export type StatusBarConfig = z.infer<typeof statusBarConfigSchema>

export interface StatusBarState extends StatusBarConfig {
  lastUpdated: string
}

export const statusTextConfigSchema = z.object({
  text: z.string(),
  isVisible: z.boolean().default(true),
  position: z.enum(['top', 'bottom']).default('bottom'),
  fontSize: z.enum(['small', 'medium', 'large']).default('medium'),
  animation: z.enum(['none', 'fade', 'slide', 'typewriter']).default('fade')
})

export type StatusTextConfig = z.infer<typeof statusTextConfigSchema>

export interface StatusTextState extends StatusTextConfig {
  lastUpdated: string
}
