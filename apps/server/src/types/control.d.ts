import { z } from 'zod'
export declare const emoteRainConfigSchema: z.ZodObject<
  {
    size: z.ZodDefault<z.ZodNumber>
    lifetime: z.ZodDefault<z.ZodNumber>
    gravity: z.ZodDefault<z.ZodNumber>
    restitution: z.ZodDefault<z.ZodNumber>
    friction: z.ZodDefault<z.ZodNumber>
    airFriction: z.ZodDefault<z.ZodNumber>
    spawnDelay: z.ZodDefault<z.ZodNumber>
    maxEmotes: z.ZodDefault<z.ZodNumber>
    rotationSpeed: z.ZodDefault<z.ZodNumber>
  },
  'strip',
  z.ZodTypeAny,
  {
    size: number
    lifetime: number
    gravity: number
    restitution: number
    friction: number
    airFriction: number
    spawnDelay: number
    maxEmotes: number
    rotationSpeed: number
  },
  {
    size?: number | undefined
    lifetime?: number | undefined
    gravity?: number | undefined
    restitution?: number | undefined
    friction?: number | undefined
    airFriction?: number | undefined
    spawnDelay?: number | undefined
    maxEmotes?: number | undefined
    rotationSpeed?: number | undefined
  }
>
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
  data: {
    id: string
    type?: string
  }
}
export interface ActivityEvent {
  id: string
  type: string
  timestamp: string
  data: unknown
}
export declare const statusBarModeSchema: z.ZodEnum<['preshow', 'soapbox', 'game', 'outro', 'break', 'custom']>
export type StatusBarMode = z.infer<typeof statusBarModeSchema>
export declare const statusBarConfigSchema: z.ZodObject<
  {
    mode: z.ZodEnum<['preshow', 'soapbox', 'game', 'outro', 'break', 'custom']>
    text: z.ZodOptional<z.ZodString>
    isVisible: z.ZodDefault<z.ZodBoolean>
    position: z.ZodDefault<z.ZodEnum<['top', 'bottom']>>
  },
  'strip',
  z.ZodTypeAny,
  {
    isVisible: boolean
    mode: 'preshow' | 'custom' | 'game' | 'soapbox' | 'outro' | 'break'
    position: 'bottom' | 'top'
    text?: string | undefined
  },
  {
    mode: 'preshow' | 'custom' | 'game' | 'soapbox' | 'outro' | 'break'
    isVisible?: boolean | undefined
    text?: string | undefined
    position?: 'bottom' | 'top' | undefined
  }
>
export type StatusBarConfig = z.infer<typeof statusBarConfigSchema>
export interface StatusBarState extends StatusBarConfig {
  lastUpdated: string
}
export declare const statusTextConfigSchema: z.ZodObject<
  {
    text: z.ZodString
    isVisible: z.ZodDefault<z.ZodBoolean>
    position: z.ZodDefault<z.ZodEnum<['top', 'bottom']>>
    fontSize: z.ZodDefault<z.ZodEnum<['small', 'medium', 'large']>>
    animation: z.ZodDefault<z.ZodEnum<['none', 'fade', 'slide', 'typewriter']>>
  },
  'strip',
  z.ZodTypeAny,
  {
    isVisible: boolean
    text: string
    position: 'bottom' | 'top'
    fontSize: 'medium' | 'small' | 'large'
    animation: 'fade' | 'none' | 'slide' | 'typewriter'
  },
  {
    text: string
    isVisible?: boolean | undefined
    position?: 'bottom' | 'top' | undefined
    fontSize?: 'medium' | 'small' | 'large' | undefined
    animation?: 'fade' | 'none' | 'slide' | 'typewriter' | undefined
  }
>
export type StatusTextConfig = z.infer<typeof statusTextConfigSchema>
export interface StatusTextState extends StatusTextConfig {
  lastUpdated: string
}
//# sourceMappingURL=control.d.ts.map
