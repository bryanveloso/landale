/**
 * Form Validation Utilities
 *
 * Provides consistent validation patterns across dashboard forms.
 * Follows project patterns for error handling and user feedback.
 */

export interface ValidationRule<T> {
  validate: (value: T) => boolean
  message: string
}

export interface ValidationResult {
  isValid: boolean
  errors: string[]
}

export interface FieldValidationResult {
  isValid: boolean
  error?: string
}

/**
 * Validates a single field with multiple rules
 */
export function validateField<T>(value: T, rules: ValidationRule<T>[]): FieldValidationResult {
  for (const rule of rules) {
    if (!rule.validate(value)) {
      return {
        isValid: false,
        error: rule.message
      }
    }
  }

  return { isValid: true }
}

/**
 * Validates an entire form object
 */
export function validateForm<T extends Record<string, unknown>>(
  data: T,
  rules: Partial<Record<keyof T, ValidationRule<unknown>[]>>
): ValidationResult {
  const errors: string[] = []

  for (const [field, fieldRules] of Object.entries(rules)) {
    const fieldValue = data[field]
    const result = validateField(fieldValue, fieldRules as ValidationRule<unknown>[])

    if (!result.isValid && result.error) {
      errors.push(`${field}: ${result.error}`)
    }
  }

  return {
    isValid: errors.length === 0,
    errors
  }
}

// Common validation rules
export const ValidationRules = {
  required: <T>(message = 'This field is required'): ValidationRule<T> => ({
    validate: (value) => value !== null && value !== undefined && value !== '',
    message
  }),

  minLength: (min: number, message?: string): ValidationRule<string> => ({
    validate: (value) => typeof value === 'string' && value.length >= min,
    message: message || `Must be at least ${min} characters`
  }),

  maxLength: (max: number, message?: string): ValidationRule<string> => ({
    validate: (value) => typeof value === 'string' && value.length <= max,
    message: message || `Must be no more than ${max} characters`
  }),

  pattern: (regex: RegExp, message: string): ValidationRule<string> => ({
    validate: (value) => typeof value === 'string' && regex.test(value),
    message
  }),

  numeric: (message = 'Must be a number'): ValidationRule<unknown> => ({
    validate: (value) => !isNaN(Number(value)),
    message
  }),

  range: (min: number, max: number, message?: string): ValidationRule<number> => ({
    validate: (value) => typeof value === 'number' && value >= min && value <= max,
    message: message || `Must be between ${min} and ${max}`
  }),

  url: (message = 'Must be a valid URL'): ValidationRule<string> => ({
    validate: (value) => {
      try {
        new URL(value)
        return true
      } catch {
        return false
      }
    },
    message
  }),

  email: (message = 'Must be a valid email address'): ValidationRule<string> => ({
    validate: (value) => {
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
      return typeof value === 'string' && emailRegex.test(value)
    },
    message
  })
}

// Stream-specific validation rules
export const StreamValidationRules = {
  streamTitle: [
    ValidationRules.required<string>('Stream title is required'),
    ValidationRules.maxLength(140, 'Stream title must be 140 characters or less')
  ] as ValidationRule<string>[],

  gameCategory: [ValidationRules.required<string>('Game category is required')] as ValidationRule<string>[],

  language: [
    ValidationRules.required<string>('Language is required'),
    ValidationRules.pattern(/^[a-z]{2}$/, 'Language must be a valid 2-letter code')
  ] as ValidationRule<string>[],

  alertMessage: [
    ValidationRules.required('Alert message is required'),
    ValidationRules.minLength(3, 'Alert message must be at least 3 characters'),
    ValidationRules.maxLength(500, 'Alert message must be 500 characters or less')
  ],

  duration: [
    ValidationRules.required('Duration is required'),
    ValidationRules.numeric('Duration must be a number'),
    ValidationRules.range(1000, 300000, 'Duration must be between 1 and 300 seconds')
  ],

  takeoverMessage: [
    ValidationRules.required('Takeover message is required'),
    ValidationRules.minLength(1, 'Takeover message cannot be empty'),
    ValidationRules.maxLength(200, 'Takeover message must be 200 characters or less')
  ]
}

/**
 * Creates a validation function for a specific form
 */
export function createFormValidator<T extends Record<string, unknown>>(
  rules: Partial<Record<keyof T, ValidationRule<unknown>[]>>
) {
  return (data: T): ValidationResult => validateForm(data, rules)
}

/**
 * Sanitizes form input by trimming whitespace and normalizing values
 */
export function sanitizeFormData<T extends Record<string, unknown>>(data: T): T {
  const sanitized: Record<string, unknown> = {}

  for (const [key, value] of Object.entries(data)) {
    if (typeof value === 'string') {
      sanitized[key] = value.trim()
    } else {
      sanitized[key] = value
    }
  }

  return sanitized as T
}

/**
 * Utility to create reactive validation for SolidJS forms
 */
export function createFieldValidator<T>(rules: ValidationRule<T>[]) {
  return (value: T) => validateField(value, rules)
}
