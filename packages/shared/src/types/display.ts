import type { z } from 'zod'

export interface Display<T = unknown> {
  id: string
  schema: z.ZodSchema<T>
  data: T
  isVisible: boolean
  metadata?: Record<string, unknown>
  lastUpdated: string
}
