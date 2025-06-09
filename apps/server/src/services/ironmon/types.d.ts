import { z } from 'zod'
export declare enum Game {
  RubySapphire = 1,
  Emerald = 2,
  FireRedLeafGreen = 3
}
export declare const initMessageSchema: z.ZodObject<
  {
    type: z.ZodLiteral<'init'>
    metadata: z.ZodObject<
      {
        version: z.ZodString
        game: z.ZodNativeEnum<typeof Game>
      },
      'strip',
      z.ZodTypeAny,
      {
        version: string
        game: Game
      },
      {
        version: string
        game: Game
      }
    >
  },
  'strip',
  z.ZodTypeAny,
  {
    type: 'init'
    metadata: {
      version: string
      game: Game
    }
  },
  {
    type: 'init'
    metadata: {
      version: string
      game: Game
    }
  }
>
export declare const seedMessageSchema: z.ZodObject<
  {
    type: z.ZodLiteral<'seed'>
    metadata: z.ZodObject<
      {
        count: z.ZodNumber
      },
      'strip',
      z.ZodTypeAny,
      {
        count: number
      },
      {
        count: number
      }
    >
  },
  'strip',
  z.ZodTypeAny,
  {
    type: 'seed'
    metadata: {
      count: number
    }
  },
  {
    type: 'seed'
    metadata: {
      count: number
    }
  }
>
export declare const checkpointMessageSchema: z.ZodObject<
  {
    type: z.ZodLiteral<'checkpoint'>
    metadata: z.ZodObject<
      {
        id: z.ZodNumber
        name: z.ZodString
        seed: z.ZodOptional<z.ZodNumber>
      },
      'strip',
      z.ZodTypeAny,
      {
        id: number
        name: string
        seed?: number | undefined
      },
      {
        id: number
        name: string
        seed?: number | undefined
      }
    >
  },
  'strip',
  z.ZodTypeAny,
  {
    type: 'checkpoint'
    metadata: {
      id: number
      name: string
      seed?: number | undefined
    }
  },
  {
    type: 'checkpoint'
    metadata: {
      id: number
      name: string
      seed?: number | undefined
    }
  }
>
export declare const locationMessageSchema: z.ZodObject<
  {
    type: z.ZodLiteral<'location'>
    metadata: z.ZodObject<
      {
        id: z.ZodNumber
      },
      'strip',
      z.ZodTypeAny,
      {
        id: number
      },
      {
        id: number
      }
    >
  },
  'strip',
  z.ZodTypeAny,
  {
    type: 'location'
    metadata: {
      id: number
    }
  },
  {
    type: 'location'
    metadata: {
      id: number
    }
  }
>
export declare const ironmonMessageSchema: z.ZodDiscriminatedUnion<
  'type',
  [
    z.ZodObject<
      {
        type: z.ZodLiteral<'init'>
        metadata: z.ZodObject<
          {
            version: z.ZodString
            game: z.ZodNativeEnum<typeof Game>
          },
          'strip',
          z.ZodTypeAny,
          {
            version: string
            game: Game
          },
          {
            version: string
            game: Game
          }
        >
      },
      'strip',
      z.ZodTypeAny,
      {
        type: 'init'
        metadata: {
          version: string
          game: Game
        }
      },
      {
        type: 'init'
        metadata: {
          version: string
          game: Game
        }
      }
    >,
    z.ZodObject<
      {
        type: z.ZodLiteral<'seed'>
        metadata: z.ZodObject<
          {
            count: z.ZodNumber
          },
          'strip',
          z.ZodTypeAny,
          {
            count: number
          },
          {
            count: number
          }
        >
      },
      'strip',
      z.ZodTypeAny,
      {
        type: 'seed'
        metadata: {
          count: number
        }
      },
      {
        type: 'seed'
        metadata: {
          count: number
        }
      }
    >,
    z.ZodObject<
      {
        type: z.ZodLiteral<'checkpoint'>
        metadata: z.ZodObject<
          {
            id: z.ZodNumber
            name: z.ZodString
            seed: z.ZodOptional<z.ZodNumber>
          },
          'strip',
          z.ZodTypeAny,
          {
            id: number
            name: string
            seed?: number | undefined
          },
          {
            id: number
            name: string
            seed?: number | undefined
          }
        >
      },
      'strip',
      z.ZodTypeAny,
      {
        type: 'checkpoint'
        metadata: {
          id: number
          name: string
          seed?: number | undefined
        }
      },
      {
        type: 'checkpoint'
        metadata: {
          id: number
          name: string
          seed?: number | undefined
        }
      }
    >,
    z.ZodObject<
      {
        type: z.ZodLiteral<'location'>
        metadata: z.ZodObject<
          {
            id: z.ZodNumber
          },
          'strip',
          z.ZodTypeAny,
          {
            id: number
          },
          {
            id: number
          }
        >
      },
      'strip',
      z.ZodTypeAny,
      {
        type: 'location'
        metadata: {
          id: number
        }
      },
      {
        type: 'location'
        metadata: {
          id: number
        }
      }
    >
  ]
>
export type InitMessage = z.infer<typeof initMessageSchema>
export type SeedMessage = z.infer<typeof seedMessageSchema>
export type CheckpointMessage = z.infer<typeof checkpointMessageSchema>
export type LocationMessage = z.infer<typeof locationMessageSchema>
export type IronmonMessage = z.infer<typeof ironmonMessageSchema>
export type IronmonEvent = {
  init: InitMessage & {
    source: 'tcp'
  }
  seed: SeedMessage & {
    source: 'tcp'
    seed: number
  }
  checkpoint: CheckpointMessage & {
    source: 'tcp'
    seed: number
    metadata: CheckpointMessage['metadata'] & {
      next?: {
        trainer: string | null
        clearRate: number
        lastCleared: number | null
      }
    }
  }
  location: LocationMessage & {
    source: 'tcp'
  }
}
export interface TCPMessage {
  length: number
  data: string
}
//# sourceMappingURL=types.d.ts.map
