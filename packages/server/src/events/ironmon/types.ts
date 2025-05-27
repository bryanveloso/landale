import { z } from 'zod'

// Game enum matching the client-side enum
export enum Game {
  RubySapphire = 1,
  Emerald = 2,
  FireRedLeafGreen = 3
}

// Base message schemas
export const initMessageSchema = z.object({
  type: z.literal('init'),
  metadata: z.object({
    version: z.string(),
    game: z.nativeEnum(Game)
  })
})

export const seedMessageSchema = z.object({
  type: z.literal('seed'),
  metadata: z.object({
    count: z.number()
  })
})

export const checkpointMessageSchema = z.object({
  type: z.literal('checkpoint'),
  metadata: z.object({
    id: z.number(),
    name: z.string(),
    seed: z.number().optional()
  })
})

export const locationMessageSchema = z.object({
  type: z.literal('location'),
  metadata: z.object({
    id: z.number()
  })
})

// Union of all message types
export const ironmonMessageSchema = z.discriminatedUnion('type', [
  initMessageSchema,
  seedMessageSchema,
  checkpointMessageSchema,
  locationMessageSchema
])

// Type exports
export type InitMessage = z.infer<typeof initMessageSchema>
export type SeedMessage = z.infer<typeof seedMessageSchema>
export type CheckpointMessage = z.infer<typeof checkpointMessageSchema>
export type LocationMessage = z.infer<typeof locationMessageSchema>
export type IronmonMessage = z.infer<typeof ironmonMessageSchema>

// Event types for the event emitter
export type IronmonEvent = {
  init: InitMessage & { source: 'tcp' }
  seed: SeedMessage & { source: 'tcp'; seed: number }
  checkpoint: CheckpointMessage & {
    source: 'tcp'
    seed: number
    metadata: CheckpointMessage['metadata'] & {
      next?: {
        trainer: string | null
        clearRate: number
        lastCleared: number | null
      }
    }
  }
  location: LocationMessage & { source: 'tcp' }
}

// TCP message format (with length prefix)
export interface TCPMessage {
  length: number
  data: string
}
