import type { Display } from '../types/display'

export interface UseDisplayOptions {
  onData?: (data: unknown) => void
  onError?: (error: Error) => void
}

export interface UseDisplayReturn<T> {
  data: T | null
  display: Display<T> | null
  isConnected: boolean
  isVisible: boolean
  update: (data: Partial<T>) => Promise<void>
  setVisibility: (isVisible: boolean) => Promise<void>
  clear: () => Promise<void>
}

// This is the interface that each package (dashboard/overlays) will implement
export interface UseDisplay {
  <T = unknown>(displayId: string, options?: UseDisplayOptions): UseDisplayReturn<T>
}
