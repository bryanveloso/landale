import type { z } from 'zod'

export interface Display<T = any> {
  id: string
  schema: z.ZodSchema<T>
  data: T
  isVisible: boolean
  metadata?: Record<string, any>
  lastUpdated: string
}