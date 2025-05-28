/**
 * Shared IronMON types used by both server and overlay packages
 */

export enum Game {
  RubySapphire = 1,
  Emerald = 2,
  FireRedLeafGreen = 3
}

export interface InitMessage {
  type: 'init'
  metadata: {
    version: string
    game: Game
  }
}

export interface SeedMessage {
  type: 'seed'
  metadata: {
    count: number
  }
}

export interface CheckpointMessage {
  type: 'checkpoint'
  metadata: {
    id: number
    name: string
    next?: {
      trainer: string | null
      clearRate: number
      lastCleared: number | null
    }
  }
}

export type IronmonMessage = InitMessage | SeedMessage | CheckpointMessage

// Re-export checkpoint data
export * from './ironmon/checkpoints'
