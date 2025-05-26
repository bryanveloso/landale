import prisma from 'database'
import { eventEmitter } from '@/events'
import type { CheckpointMessage, SeedMessage, InitMessage, IronmonEvent } from './types'

/**
 * Service layer for checkpoint operations
 */
class CheckpointService {
  async recordCheckpointClear(checkpointId: number, seedId: number) {
    if (checkpointId <= 0) return

    await prisma.result.upsert({
      where: {
        seedId_checkpointId: { checkpointId, seedId }
      },
      update: {},
      create: { checkpointId, seedId, result: true }
    })
  }

  async getNextCheckpointInfo(checkpointId: number) {
    const nextId = checkpointId + 1

    // Get trainer info for next checkpoint
    const checkpoint = await prisma.checkpoint.findUnique({
      where: { id: nextId },
      select: { trainer: true }
    })

    // Calculate clear rate
    const [clearCount, seedCount] = await Promise.all([
      prisma.result.count({ where: { checkpointId: nextId } }),
      prisma.seed.count()
    ])

    const clearRate = seedCount > 0 
      ? Math.round((clearCount / seedCount) * 10000) / 100 
      : 0

    // Get last cleared seed
    const lastCleared = await prisma.result.findFirst({
      where: { checkpointId: nextId },
      orderBy: { seedId: 'desc' },
      select: { seedId: true }
    })

    return {
      trainer: checkpoint?.trainer || null,
      clearRate,
      lastCleared: lastCleared?.seedId || null
    }
  }
}

/**
 * Service layer for seed operations
 */
class SeedService {
  async recordSeed(seedId: number) {
    await prisma.seed.upsert({
      where: { id: seedId },
      update: {},
      create: { 
        id: seedId,
        challengeId: 1 // Default challenge ID
      }
    })
  }
}

// Service instances
const checkpointService = new CheckpointService()
const seedService = new SeedService()

/**
 * Handles checkpoint messages from IronMON
 */
export async function handleCheckpoint(message: CheckpointMessage): Promise<IronmonEvent['checkpoint']> {
  const { metadata, seed } = message

  // Record the checkpoint clear
  await checkpointService.recordCheckpointClear(metadata.id, seed)

  // Get info about the next checkpoint
  const nextInfo = await checkpointService.getNextCheckpointInfo(metadata.id)

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

  // Record the seed
  await seedService.recordSeed(metadata.count)

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