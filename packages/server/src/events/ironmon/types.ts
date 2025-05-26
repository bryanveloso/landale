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
  seed: z.number(),
  metadata: z.object({
    count: z.number()
  })
})

export const checkpointMessageSchema = z.object({
  type: z.literal('checkpoint'),
  seed: z.number(),
  metadata: z.object({
    id: z.number(),
    name: z.string()
  })
})

// Union of all message types
export const ironmonMessageSchema = z.discriminatedUnion('type', [
  initMessageSchema,
  seedMessageSchema,
  checkpointMessageSchema
])

// Type exports
export type InitMessage = z.infer<typeof initMessageSchema>
export type SeedMessage = z.infer<typeof seedMessageSchema>
export type CheckpointMessage = z.infer<typeof checkpointMessageSchema>
export type IronmonMessage = z.infer<typeof ironmonMessageSchema>

// Event types for the event emitter
export type IronmonEvent = {
  init: InitMessage & { source: 'tcp' }
  seed: SeedMessage & { source: 'tcp' }
  checkpoint: CheckpointMessage & {
    source: 'tcp'
    metadata: CheckpointMessage['metadata'] & {
      next?: {
        trainer: string | null
        clearRate: number
        lastCleared: number | null
      }
    }
  }
}

// TCP message format (with length prefix)
export interface TCPMessage {
  length: number
  data: string
}
