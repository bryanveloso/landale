import type { ZodSchema } from 'zod'
import { eventEmitter } from '@/events'
import type { EventMap } from '@/events/types'
import { createLogger } from '@landale/logger'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'display-manager' })

export interface Display<T = unknown> {
  id: string
  schema: ZodSchema<T>
  data: T
  isVisible: boolean
  metadata?: Record<string, unknown>
  lastUpdated: string
}

export class DisplayManager {
  private displays = new Map<string, Display>()

  /**
   * Register a new display with schema validation
   */
  register<T>(id: string, schema: ZodSchema<T>, defaultData: T, metadata?: Record<string, unknown>): void {
    if (this.displays.has(id)) {
      log.warn('Display already registered, skipping', { metadata: { displayId: id } })
      return
    }

    // Validate default data
    const validatedData = schema.parse(defaultData)

    const display: Display<T> = {
      id,
      schema,
      data: validatedData,
      isVisible: true,
      metadata,
      lastUpdated: new Date().toISOString()
    }

    this.displays.set(id, display)
    log.info('Registered display', { metadata: { displayId: id } })
  }

  /**
   * Update display data with validation
   */
  update<T>(id: string, data: Partial<T>): Display<T> {
    const display = this.displays.get(id)
    if (!display) {
      throw new Error(`Display ${id} not registered`)
    }

    // Merge and validate
    const merged = { ...(display.data as T), ...data }
    const validated = display.schema.parse(merged)

    // Update display
    display.data = validated
    display.lastUpdated = new Date().toISOString()

    // Emit update event
    void eventEmitter.emit(`display:${id}:update`, display)

    log.debug('Updated display', { metadata: { displayId: id, data: validated } })

    return display as Display<T>
  }

  /**
   * Update display visibility
   */
  setVisibility(id: string, isVisible: boolean): Display {
    const display = this.displays.get(id)
    if (!display) {
      throw new Error(`Display ${id} not registered`)
    }

    display.isVisible = isVisible
    display.lastUpdated = new Date().toISOString()

    void eventEmitter.emit(`display:${id}:update`, display)

    return display
  }

  /**
   * Get display by ID
   */
  get<T>(id: string): Display<T> | undefined {
    return this.displays.get(id) as Display<T> | undefined
  }

  /**
   * Get display data (throws if not found)
   */
  getData(id: string): unknown {
    const display = this.get(id)
    if (!display) {
      throw new Error(`Display ${id} not found`)
    }
    return display.data
  }

  /**
   * List all registered displays
   */
  list(): Display[] {
    return Array.from(this.displays.values())
  }

  /**
   * Check if display exists
   */
  has(id: string): boolean {
    return this.displays.has(id)
  }

  /**
   * Clear display data (reset to default)
   */
  clear(id: string): void {
    const display = this.displays.get(id)
    if (!display) {
      throw new Error(`Display ${id} not registered`)
    }

    // Parse empty object to get defaults
    const defaultData = display.schema.parse({})
    display.data = defaultData
    display.lastUpdated = new Date().toISOString()

    void eventEmitter.emit(`display:${id}:update` as keyof EventMap, display)
  }

  /**
   * Append to array field in display
   */
  append<T>(id: string, field: string, item: unknown, maxItems?: number): Display<T> {
    const display = this.get<T>(id)
    if (!display) {
      throw new Error(`Display ${id} not found`)
    }

    const data = display.data as Record<string, unknown>
    if (!Array.isArray(data[field])) {
      throw new Error(`Field ${field} is not an array`)
    }

    // Append and trim if needed
    const arrayField = data[field] as unknown[]
    arrayField.push(item)
    if (maxItems && arrayField.length > maxItems) {
      data[field] = arrayField.slice(-maxItems)
    }

    return this.update(id, data as Partial<T>)
  }
}

// Create singleton instance
export const displayManager = new DisplayManager()
