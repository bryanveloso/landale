import prisma from '@landale/database'
import { createLogger } from '@/lib/logger'

const log = createLogger('database')

/**
 * Optimized database service with query patterns
 */
export class DatabaseService {
  /**
   * Get active challenge with minimal data
   */
  async getActiveChallenge(seedId: string) {
    return prisma.challenge.findFirst({
      where: {
        seeds: {
          some: { id: parseInt(seedId) }
        }
      },
      select: {
        id: true,
        name: true,
        checkpoints: {
          select: {
            id: true,
            name: true,
            trainer: true,
            order: true
          },
          orderBy: { order: 'asc' }
        }
      }
    })
  }

  /**
   * Record checkpoint clear with transaction
   */
  async recordCheckpointClear(checkpointId: number, seedId: number) {
    if (checkpointId <= 0) return null

    try {
      return await prisma.$transaction(async (tx) => {
        // Upsert the result
        const result = await tx.result.upsert({
          where: {
            seedId_checkpointId: { checkpointId, seedId }
          },
          update: {},
          create: { checkpointId, seedId, result: true },
          select: {
            id: true,
            seedId: true,
            checkpointId: true
          }
        })

        log.debug(`Recorded checkpoint clear: seed=${seedId}, checkpoint=${checkpointId}`)
        return result
      })
    } catch (error) {
      log.error('Failed to record checkpoint clear', error)
      throw error
    }
  }

  /**
   * Get checkpoint statistics efficiently
   */
  async getCheckpointStats(checkpointId: number) {
    const [checkpoint, stats] = await prisma.$transaction([
      // Get checkpoint details
      prisma.checkpoint.findUnique({
        where: { id: checkpointId },
        select: {
          id: true,
          trainer: true,
          name: true,
          order: true
        }
      }),

      // Get aggregated stats
      prisma.result.aggregate({
        where: { checkpointId },
        _count: { _all: true },
        _max: { seedId: true }
      })
    ])

    // Get total seed count (can be cached)
    const seedCount = await this.getCachedSeedCount()

    const clearRate = seedCount > 0 ? Math.round((stats._count._all / seedCount) * 10000) / 100 : 0

    return {
      checkpoint,
      clearCount: stats._count._all,
      clearRate,
      lastClearedSeed: stats._max.seedId
    }
  }

  /**
   * Batch upsert seeds for performance
   */
  async batchUpsertSeeds(seedIds: number[], challengeId: number = 1) {
    const seeds = seedIds.map((id) => ({
      id,
      challengeId
    }))

    // Use createMany with skipDuplicates for efficiency
    const result = await prisma.seed.createMany({
      data: seeds,
      skipDuplicates: true
    })

    log.debug(`Batch upserted ${result.count} seeds`)
    return result
  }

  /**
   * Get recent results with pagination
   */
  async getRecentResults(limit: number = 10, cursor?: number) {
    return prisma.result.findMany({
      take: limit,
      skip: cursor ? 1 : 0,
      cursor: cursor ? { id: cursor } : undefined,
      orderBy: { id: 'desc' },
      select: {
        id: true,
        seedId: true,
        checkpointId: true,
        result: true,
        seed: {
          select: { id: true }
        },
        checkpoint: {
          select: {
            id: true,
            name: true,
            trainer: true
          }
        }
      }
    })
  }

  // Cache seed count for 5 minutes
  private seedCountCache: { count: number; timestamp: number } | null = null
  private readonly CACHE_DURATION = 5 * 60 * 1000 // 5 minutes

  private async getCachedSeedCount(): Promise<number> {
    const now = Date.now()

    if (!this.seedCountCache || now - this.seedCountCache.timestamp > this.CACHE_DURATION) {
      const count = await prisma.seed.count()
      this.seedCountCache = { count, timestamp: now }
    }

    return this.seedCountCache.count
  }

  /**
   * Clear the seed count cache
   */
  clearSeedCountCache() {
    this.seedCountCache = null
  }

  /**
   * Get info about the next checkpoint
   */
  async getNextCheckpointInfo(checkpointId: number) {
    const nextId = checkpointId + 1

    // Get trainer info for next checkpoint
    const checkpoint = await prisma.checkpoint.findUnique({
      where: { id: nextId },
      select: { trainer: true }
    })

    // Calculate clear rate using optimized query
    const [clearCount, seedCount] = await Promise.all([
      prisma.result.count({ where: { checkpointId: nextId } }),
      this.getCachedSeedCount()
    ])

    const clearRate = seedCount > 0 ? Math.round((clearCount / seedCount) * 10000) / 100 : 0

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

  /**
   * Record seeds using batch operation
   */
  async recordSeeds(seedIds: number[], challengeId: number = 1) {
    return this.batchUpsertSeeds(seedIds, challengeId)
  }
}

// Export singleton instance
export const databaseService = new DatabaseService()
