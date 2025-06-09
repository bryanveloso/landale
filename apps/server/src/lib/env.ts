import { z } from 'zod'
import { createLogger } from './logger'

const log = createLogger('env')

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
  RAINWAVE_USER_ID: z.string().optional().describe('Rainwave user ID')
})

// Parse and validate environment variables
function validateEnv() {
  const parsed = envSchema.safeParse(process.env)

  if (!parsed.success) {
    log.error('❌ Environment validation failed!')
    console.error('\nMissing or invalid environment variables:')

    const errors = parsed.error.format()
    Object.entries(errors).forEach(([key, value]) => {
      if (key !== '_errors' && value && '_errors' in value) {
        console.error(`  ${key}: ${value._errors.join(', ')}`)
      }
    })

    console.error('\nPlease check your .env file or environment configuration.\n')
    process.exit(1)
  }

  return parsed.data
}

// Export validated environment variables
export const env = validateEnv()

// Type-safe environment variable access
export type Env = z.infer<typeof envSchema>
