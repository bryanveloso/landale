/**
 * @landale/shared - Shared types and utilities for the Landale overlay system
 */

export * from './ironmon'
export * from './twitch'
export * from './obs'
export * from './types/display'
export * from './types/music'
export * from './types/apple-music'
export type * from './hooks/use-display'

// Common utility types
export type DeepPartial<T> = T extends object
  ? {
      [P in keyof T]?: DeepPartial<T[P]>
    }
  : T

export type Nullable<T> = T | null | undefined
