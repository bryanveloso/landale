/**
 * @landale/shared - Shared types and utilities for the Landale overlay system
 */

export * from './ironmon'
export * from './twitch'

// Common utility types
export type DeepPartial<T> = T extends object
  ? {
      [P in keyof T]?: DeepPartial<T[P]>
    }
  : T

export type Nullable<T> = T | null | undefined
