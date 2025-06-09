/**
 * Optimized database service with query patterns
 */
export declare class DatabaseService {
  /**
   * Get active challenge with minimal data
   */
  getActiveChallenge(seedId: string): Promise<any>
  /**
   * Record checkpoint clear with transaction
   */
  recordCheckpointClear(checkpointId: number, seedId: number): Promise<any>
  /**
   * Get checkpoint statistics efficiently
   */
  getCheckpointStats(checkpointId: number): Promise<{
    checkpoint: any
    clearCount: any
    clearRate: number
    lastClearedSeed: any
  }>
  /**
   * Batch upsert seeds for performance
   */
  batchUpsertSeeds(seedIds: number[], challengeId?: number): Promise<any>
  /**
   * Get recent results with pagination
   */
  getRecentResults(limit?: number, cursor?: number): Promise<any>
  private seedCountCache
  private readonly CACHE_DURATION
  private getCachedSeedCount
  /**
   * Clear the seed count cache
   */
  clearSeedCountCache(): void
  /**
   * Get info about the next checkpoint
   */
  getNextCheckpointInfo(checkpointId: number): Promise<{
    trainer: any
    clearRate: number
    lastCleared: any
  }>
  /**
   * Record seeds using batch operation
   */
  recordSeeds(seedIds: number[], challengeId?: number): Promise<any>
}
export declare const databaseService: DatabaseService
//# sourceMappingURL=database.d.ts.map
