import { z } from 'zod'
declare const envSchema: z.ZodObject<
  {
    DATABASE_URL: z.ZodString
    TWITCH_CLIENT_ID: z.ZodString
    TWITCH_CLIENT_SECRET: z.ZodString
    TWITCH_EVENTSUB_SECRET: z.ZodString
    TWITCH_USER_ID: z.ZodString
    NODE_ENV: z.ZodDefault<z.ZodEnum<['development', 'production', 'test']>>
    LOG_LEVEL: z.ZodOptional<z.ZodDefault<z.ZodEnum<['error', 'warn', 'info', 'debug']>>>
    STRUCTURED_LOGGING: z.ZodOptional<z.ZodDefault<z.ZodEffects<z.ZodString, boolean, string>>>
    CONTROL_API_KEY: z.ZodOptional<z.ZodDefault<z.ZodString>>
    APPLE_TEAM_ID: z.ZodOptional<z.ZodString>
    APPLE_KEY_ID: z.ZodOptional<z.ZodString>
    APPLE_PRIVATE_KEY: z.ZodOptional<z.ZodString>
  },
  'strip',
  z.ZodTypeAny,
  {
    DATABASE_URL: string
    TWITCH_CLIENT_ID: string
    TWITCH_CLIENT_SECRET: string
    TWITCH_EVENTSUB_SECRET: string
    TWITCH_USER_ID: string
    NODE_ENV: 'development' | 'production' | 'test'
    LOG_LEVEL?: 'error' | 'warn' | 'info' | 'debug' | undefined
    STRUCTURED_LOGGING?: boolean | undefined
    CONTROL_API_KEY?: string | undefined
    APPLE_TEAM_ID?: string | undefined
    APPLE_KEY_ID?: string | undefined
    APPLE_PRIVATE_KEY?: string | undefined
  },
  {
    DATABASE_URL: string
    TWITCH_CLIENT_ID: string
    TWITCH_CLIENT_SECRET: string
    TWITCH_EVENTSUB_SECRET: string
    TWITCH_USER_ID: string
    NODE_ENV?: 'development' | 'production' | 'test' | undefined
    LOG_LEVEL?: 'error' | 'warn' | 'info' | 'debug' | undefined
    STRUCTURED_LOGGING?: string | undefined
    CONTROL_API_KEY?: string | undefined
    APPLE_TEAM_ID?: string | undefined
    APPLE_KEY_ID?: string | undefined
    APPLE_PRIVATE_KEY?: string | undefined
  }
>
export declare const env: {
  DATABASE_URL: string
  TWITCH_CLIENT_ID: string
  TWITCH_CLIENT_SECRET: string
  TWITCH_EVENTSUB_SECRET: string
  TWITCH_USER_ID: string
  NODE_ENV: 'development' | 'production' | 'test'
  LOG_LEVEL?: 'error' | 'warn' | 'info' | 'debug' | undefined
  STRUCTURED_LOGGING?: boolean | undefined
  CONTROL_API_KEY?: string | undefined
  APPLE_TEAM_ID?: string | undefined
  APPLE_KEY_ID?: string | undefined
  APPLE_PRIVATE_KEY?: string | undefined
}
export type Env = z.infer<typeof envSchema>
export {}
//# sourceMappingURL=env.d.ts.map
