import { eventEmitter } from '@/events'
import { StatusBarService } from './status-bar'

// Create singleton instances
export const statusBarService = new StatusBarService(eventEmitter)

// Re-export service classes
export { StatusBarService }