import { eventEmitter } from '@/events'
import { StatusBarService } from './status-bar'
import { StatusTextService } from './status-text'

// Create singleton instances
export const statusBarService = new StatusBarService(eventEmitter)
export const statusTextService = new StatusTextService(eventEmitter)

// Re-export service classes
export { StatusBarService, StatusTextService }