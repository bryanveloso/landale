import type { ZodSchema } from 'zod'
export interface Display<T = any> {
  id: string
  schema: ZodSchema<T>
  data: T
  isVisible: boolean
  metadata?: Record<string, any>
  lastUpdated: string
}
export declare class DisplayManager {
  private displays
  /**
   * Register a new display with schema validation
   */
  register<T>(id: string, schema: ZodSchema<T>, defaultData: T, metadata?: Record<string, any>): void
  /**
   * Update display data with validation
   */
  update<T>(id: string, data: Partial<T>): Display<T>
  /**
   * Update display visibility
   */
  setVisibility(id: string, isVisible: boolean): Display
  /**
   * Get display by ID
   */
  get<T>(id: string): Display<T> | undefined
  /**
   * Get display data (throws if not found)
   */
  getData<T>(id: string): T
  /**
   * List all registered displays
   */
  list(): Display[]
  /**
   * Check if display exists
   */
  has(id: string): boolean
  /**
   * Clear display data (reset to default)
   */
  clear(id: string): void
  /**
   * Append to array field in display
   */
  append<T>(id: string, field: string, item: any, maxItems?: number): Display<T>
}
export declare const displayManager: DisplayManager
//# sourceMappingURL=display-manager.d.ts.map
