/**
 * @landale/shared - Shared types and utilities for the Landale overlay system
 */

export * from './emotes'
export * from './ironmon'
export * from './twitch'
export * from './obs'
export * from './types/display'
export * from './types/music'
export * from './types/apple-music'
export type * from './hooks/use-display'
export { SocketProvider, useSocket } from './providers/socket-provider'
export { DEFAULT_SERVER_URLS } from './config'

// Common utility types
export type DeepPartial<T> = T extends object
  ? {
      [P in keyof T]?: DeepPartial<T[P]>
    }
  : T

export type Nullable<T> = T | null | undefined
