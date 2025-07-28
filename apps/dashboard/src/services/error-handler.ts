/**
 * Error Handler Service
 *
 * Provides consistent error handling patterns across dashboard components.
 * Standardizes error formatting, logging, and user feedback.
 */

import { createLogger } from '@landale/logger/browser'

const logger = createLogger({
  service: 'dashboard-error-handler',
  level: 'info',
  enableConsole: true
})

export interface ErrorContext {
  component?: string
  operation?: string
  data?: Record<string, unknown>
}

export interface ErrorResult {
  message: string
  userMessage: string
  logged: boolean
}

/**
 * Handles and formats errors consistently across components
 */
export function handleError(error: unknown, context: ErrorContext = {}): ErrorResult {
  const errorInfo = {
    component: context.component || 'unknown',
    operation: context.operation || 'unknown',
    data: context.data || {}
  }

  let message: string
  let userMessage: string

  if (error instanceof Error) {
    message = error.message
    userMessage = formatUserMessage(error.message, context.operation)
  } else if (typeof error === 'string') {
    message = error
    userMessage = formatUserMessage(error, context.operation)
  } else {
    message = 'Unknown error occurred'
    userMessage = `Failed to ${context.operation || 'complete operation'}`
  }

  // Log the error with context
  logger.error('Component error occurred', {
    error: {
      message,
      type: error instanceof Error ? error.constructor.name : typeof error,
      stack: error instanceof Error ? error.stack : undefined
    },
    ...errorInfo
  })

  return {
    message,
    userMessage,
    logged: true
  }
}

/**
 * Formats error messages for user display
 */
function formatUserMessage(errorMessage: string, operation?: string): string {
  // Common error patterns and their user-friendly messages
  const errorPatterns = [
    { pattern: /network/i, message: 'Network connection issue' },
    { pattern: /timeout/i, message: 'Request timed out' },
    { pattern: /rate limit/i, message: 'Too many requests, please wait' },
    { pattern: /unauthorized/i, message: 'Authentication required' },
    { pattern: /forbidden/i, message: 'Access denied' },
    { pattern: /not found/i, message: 'Resource not found' },
    { pattern: /validation/i, message: 'Invalid input provided' }
  ]

  // Check for known error patterns
  for (const { pattern, message } of errorPatterns) {
    if (pattern.test(errorMessage)) {
      return operation ? `${message} while ${operation}` : message
    }
  }

  // Default user message
  return operation ? `Failed to ${operation}` : 'An error occurred'
}

/**
 * Handles async operations with consistent error handling
 */
export async function handleAsyncOperation<T>(
  operation: () => Promise<T>,
  context: ErrorContext
): Promise<{ success: true; data: T } | { success: false; error: ErrorResult }> {
  try {
    const data = await operation()
    return { success: true, data }
  } catch (error) {
    const errorResult = handleError(error, context)
    return { success: false, error: errorResult }
  }
}

/**
 * Creates an error state setter that follows consistent patterns
 */
export function createErrorState() {
  return {
    error: null as string | null,
    hasError: false,
    setError: (message: string | null) => ({ error: message, hasError: !!message }),
    clearError: () => ({ error: null, hasError: false })
  }
}
