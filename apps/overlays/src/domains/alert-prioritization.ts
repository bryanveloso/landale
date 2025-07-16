/**
 * Alert Prioritization Domain Logic - Client Side
 * Pure functional core for alert prioritization business logic
 * 
 * Contains no side effects - all functions are pure and deterministic.
 * Maps alert types to numeric priorities and manages interrupt stack ordering.
 */

export type AlertType = 
  | 'alert' 
  | 'sub_train' 
  | 'manual_override' 
  | 'ticker'
  | 'emote_stats'
  | 'recent_follows'
  | 'death_alert'
  | 'elite_four_alert'
  | 'shiny_encounter'
  | 'level_up'
  | 'gym_badge'
  | 'cheer_celebration'
  | 'ironmon_run_stats'
  | 'ironmon_deaths'
  | 'raid_alert'
  | 'host_alert'
  | 'follow_celebration'
  | 'stream_goals'
  | 'daily_stats'
  | 'build_failure'
  | 'deployment_alert'
  | 'commit_celebration'
  | 'pr_merged'
  | 'commit_stats'
  | 'build_status'
  | string

export type PriorityLevel = 'alert' | 'sub_train' | 'ticker'

export interface Alert {
  id?: string
  type: AlertType
  priority: number
  data: unknown
  duration?: number
  startedAt?: string
}

export interface AlertCreationOptions {
  id?: string
  duration?: number
}

// Priority constants
const PRIORITY_ALERT = 100
const PRIORITY_SUB_TRAIN = 50
const PRIORITY_MANUAL_OVERRIDE = 50
const PRIORITY_TICKER = 10

// Default durations (milliseconds)
const DEFAULT_ALERT_DURATION = 10000
const DEFAULT_SUB_TRAIN_DURATION = 300000
const DEFAULT_MANUAL_OVERRIDE_DURATION = 30000
const DEFAULT_TICKER_DURATION = 15000

/**
 * Returns the numeric priority for a given alert type.
 * 
 * Priority levels:
 * - 100: High priority alerts (breaking news, critical interrupts)
 * - 50: Medium priority alerts (celebrations, notifications)
 * - 10: Low priority alerts (ticker content, ambient information)
 * 
 * Unknown alert types default to ticker priority (10).
 */
export function getPriorityForAlertType(alertType: AlertType): number {
  switch (alertType) {
    case 'alert':
      return PRIORITY_ALERT
    case 'sub_train':
      return PRIORITY_SUB_TRAIN
    case 'manual_override':
      return PRIORITY_MANUAL_OVERRIDE
    default:
      return PRIORITY_TICKER
  }
}

/**
 * Determines which alert should be actively displayed.
 * 
 * Algorithm:
 * 1. Return highest priority alert from interrupt_stack if available
 * 2. Among same priority, return first alert (FIFO)
 * 3. Fall back to ticker alert if no interrupts
 * 4. Return null if nothing available
 */
export function determineActiveAlert(
  interruptStack: (Alert | null)[], 
  tickerRotation: AlertType[]
): Alert | null {
  const highestPriorityAlert = getHighestPriorityAlert(interruptStack)
  
  if (highestPriorityAlert) {
    return highestPriorityAlert
  }
  
  return getTickerAlert(tickerRotation)
}

/**
 * Sorts alerts by priority descending, then by timestamp ascending (FIFO).
 * 
 * Higher priority alerts appear first in the list.
 * For same priority alerts, earlier startedAt timestamps appear first.
 */
export function sortAlertsByPriority(alertList: Alert[]): Alert[] {
  return alertList
    .slice() // Don't mutate original array
    .sort((a, b) => {
      if (a.priority !== b.priority) {
        return b.priority - a.priority // Higher priority first
      }
      
      // Same priority - use FIFO (earlier startedAt first)
      const aTime = a.startedAt || '1970-01-01T00:00:00Z'
      const bTime = b.startedAt || '1970-01-01T00:00:00Z'
      return aTime.localeCompare(bTime)
    })
}

/**
 * Creates an alert struct with proper priority and metadata.
 * 
 * Options:
 * - id: Custom ID (generates UUID if not provided)
 * - duration: Custom duration in milliseconds
 */
export function createAlert(
  alertType: AlertType, 
  alertData: unknown, 
  options: AlertCreationOptions = {}
): Alert {
  return {
    id: options.id || generateId(),
    type: alertType,
    priority: getPriorityForAlertType(alertType),
    data: alertData,
    duration: options.duration || getDefaultDuration(alertType),
    startedAt: new Date().toISOString()
  }
}

/**
 * Determines the overall priority level classification for an interrupt stack.
 * 
 * Returns 'alert', 'sub_train', or 'ticker' based on the highest priority
 * alert present in the interrupt stack.
 */
export function getPriorityLevel(interruptStack: Alert[]): PriorityLevel {
  if (hasAlertsWithPriority(interruptStack, PRIORITY_ALERT)) {
    return 'alert'
  }
  
  if (hasAlertsWithPriority(interruptStack, PRIORITY_SUB_TRAIN)) {
    return 'sub_train'
  }
  
  return 'ticker'
}

// Private helper functions

function getHighestPriorityAlert(interruptStack: (Alert | null)[]): Alert | null {
  const validAlerts = interruptStack.filter((alert): alert is Alert => 
    alert !== null && alert !== undefined
  )
  
  if (validAlerts.length === 0) {
    return null
  }
  
  const sorted = sortAlertsByPriority(validAlerts)
  return sorted[0]
}

function getTickerAlert(tickerRotation: AlertType[]): Alert | null {
  if (tickerRotation.length === 0) {
    return null
  }
  
  return {
    type: tickerRotation[0],
    priority: PRIORITY_TICKER,
    data: {},
    startedAt: new Date().toISOString()
  }
}

function hasAlertsWithPriority(interruptStack: Alert[], targetPriority: number): boolean {
  return interruptStack.some(alert => alert && alert.priority >= targetPriority)
}

function getDefaultDuration(alertType: AlertType): number {
  switch (alertType) {
    case 'alert':
      return DEFAULT_ALERT_DURATION
    case 'sub_train':
      return DEFAULT_SUB_TRAIN_DURATION
    case 'manual_override':
      return DEFAULT_MANUAL_OVERRIDE_DURATION
    default:
      return DEFAULT_TICKER_DURATION
  }
}

function generateId(): string {
  // Simple UUID-like ID generation for the client
  return Math.random().toString(36).substring(2, 15) + 
         Math.random().toString(36).substring(2, 15)
}