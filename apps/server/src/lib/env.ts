import { z } from 'zod'
import { createLogger } from '@landale/logger'

const logger = createLogger({ service: 'landale-server' })
const log = logger.child({ module: 'env' })

// Define the environment schema
const envSchema = z.object({
  // Database
  DATABASE_URL: z.string().url().describe('PostgreSQL connection string'),

  // Twitch Configuration
  TWITCH_CLIENT_ID: z.string().min(1).describe('Twitch application client ID'),
  TWITCH_CLIENT_SECRET: z.string().min(1).describe('Twitch application client secret'),
  TWITCH_EVENTSUB_SECRET: z.string().min(1).describe('Secret for EventSub webhook validation'),
  TWITCH_USER_ID: z.string().min(1).describe('Twitch user ID for channel subscriptions'),

  // Optional Configuration
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  LOG_LEVEL: z.enum(['error', 'warn', 'info', 'debug']).default('info').optional(),
  STRUCTURED_LOGGING: z
    .string()
    .transform((val) => val === 'true')
    .default('false')
    .optional(),

  // Control API Security
  CONTROL_API_KEY: z.string().min(32).optional().describe('API key for control endpoints (min 32 chars)'),

  // Apple Music (optional)
  APPLE_TEAM_ID: z.string().optional().describe('Apple Developer Team ID'),
  APPLE_KEY_ID: z.string().optional().describe('Apple Music Key ID'),
  APPLE_PRIVATE_KEY: z.string().optional().describe('Base64 encoded .p8 private key'),

  // Rainwave (optional)
  RAINWAVE_API_KEY: z.string().optional().describe('Rainwave API key'),
  RAINWAVE_USER_ID: z.string().optional().describe('Rainwave user ID'),
  
  // Seq Logging (optional)
  SEQ_HOST: z.string().optional().describe('Seq server hostname'),
  SEQ_PORT: z.string().optional().describe('Seq server port'),
  SEQ_API_KEY: z.string().optional().describe('Seq API key for ingestion'),
  
  // Tailscale OAuth (optional)
  TAILSCALE_CLIENT_ID: z.string().optional().describe('Tailscale OAuth client ID'),
  TAILSCALE_CLIENT_SECRET: z.string().optional().describe('Tailscale OAuth client secret')
})

// Parse and validate environment variables
function validateEnv() {
  const parsed = envSchema.safeParse(process.env)

  if (!parsed.success) {
    const errors = parsed.error.format()
    const errorDetails: Record<string, string[]> = {}

    Object.entries(errors).forEach(([key, value]) => {
      if (key === '_errors') return

      if (
        value && // eslint-disable-line @typescript-eslint/no-unnecessary-condition
        typeof value === 'object' &&
        '_errors' in value
      ) {
        const errorValue = value as Record<string, unknown>
        if (Array.isArray(errorValue._errors)) {
          errorDetails[key] = errorValue._errors as string[]
        }
      }
    })

    log.error('Environment validation failed', {
      error: new Error('Please check your .env file or environment configuration'),
      metadata: { errors: errorDetails }
    })
    process.exit(1)
  }

  return parsed.data
}

// Export validated environment variables
export const env = validateEnv()

// Type-safe environment variable access
export type Env = z.infer<typeof envSchema>
