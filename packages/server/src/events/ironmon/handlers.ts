import { eventEmitter } from '@/events'
import { databaseService } from '@/services/database'
import type { CheckpointMessage, SeedMessage, InitMessage, IronmonEvent } from './types'

/**
 * Handles checkpoint messages from IronMON
 */
export async function handleCheckpoint(message: CheckpointMessage): Promise<IronmonEvent['checkpoint']> {
  const { metadata, seed } = message

  // Record the checkpoint clear using optimized transaction
  await databaseService.recordCheckpointClear(metadata.id, seed)

  // Get info about the next checkpoint
  const nextInfo = await databaseService.getNextCheckpointInfo(metadata.id)

  // Prepare the event data
  const eventData: IronmonEvent['checkpoint'] = {
    source: 'tcp',
    type: 'checkpoint',
    seed,
    metadata: {
      ...metadata,
      next: nextInfo
    }
  }

  // Emit the event
  eventEmitter.emit('ironmon:checkpoint', eventData)

  return eventData
}

/**
 * Handles seed messages from IronMON
 */
export async function handleSeed(message: SeedMessage): Promise<IronmonEvent['seed']> {
  const { metadata } = message

  // Record the seed using batch operation
  await databaseService.recordSeeds([metadata.count])

  // Prepare the event data
  const eventData: IronmonEvent['seed'] = {
    source: 'tcp',
    type: 'seed',
    seed: metadata.count,
    metadata
  }

  // Emit the event
  eventEmitter.emit('ironmon:seed', eventData)

  return eventData
}

/**
 * Handles init messages from IronMON
 */
export async function handleInit(message: InitMessage): Promise<IronmonEvent['init']> {
  const eventData: IronmonEvent['init'] = {
    source: 'tcp',
    type: message.type,
    metadata: message.metadata
  }

  // Emit the event
  eventEmitter.emit('ironmon:init', eventData)

  return eventData
}
