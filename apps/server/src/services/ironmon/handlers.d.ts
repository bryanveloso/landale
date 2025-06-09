import type { CheckpointMessage, SeedMessage, InitMessage, LocationMessage, IronmonEvent } from './types'
/**
 * Handles checkpoint messages from IronMON Connect
 */
export declare function handleCheckpoint(message: CheckpointMessage): Promise<IronmonEvent['checkpoint']>
/**
 * Handles seed messages from IronMON Connect
 */
export declare function handleSeed(message: SeedMessage): Promise<IronmonEvent['seed']>
/**
 * Handles init messages from IronMON Connect
 */
export declare function handleInit(message: InitMessage): Promise<IronmonEvent['init']>
/**
 * Handles location messages from IronMON Connect
 */
export declare function handleLocation(message: LocationMessage): Promise<IronmonEvent['location']>
//# sourceMappingURL=handlers.d.ts.map
