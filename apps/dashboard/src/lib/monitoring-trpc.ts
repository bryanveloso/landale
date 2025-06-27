/* eslint-disable @typescript-eslint/no-unsafe-member-access */
/* eslint-disable @typescript-eslint/no-unsafe-call */
/* eslint-disable @typescript-eslint/no-unsafe-return */
/* eslint-disable @typescript-eslint/no-explicit-any */

import { trpc } from './trpc'

interface Subscription {
  unsubscribe: () => void
}

interface QueryResult<T> {
  data: T | undefined
}

export const monitoringTrpc = {
  audit: {
    getRecentEvents: {
      useQuery: (params: { limit: number; category?: string }): QueryResult<any> => {
        try {
          return (trpc as any).monitoring?.audit?.getRecentEvents?.useQuery?.(params) ?? { data: undefined }
        } catch {
          return { data: undefined }
        }
      }
    },
    onEvents: {
      subscribe: (params: undefined, handlers: { onData: (event: any) => void }): Subscription => {
        try {
          return (trpc as any).monitoring?.audit?.onEvents?.subscribe?.(params, handlers) ?? { unsubscribe: () => {} }
        } catch {
          return { unsubscribe: () => {} }
        }
      }
    }
  },
  performance: {
    onMetrics: {
      subscribe: (params: undefined, handlers: { onData: (data: any) => void }): Subscription => {
        try {
          return (
            (trpc as any).monitoring?.performance?.onMetrics?.subscribe?.(params, handlers) ?? { unsubscribe: () => {} }
          )
        } catch {
          return { unsubscribe: () => {} }
        }
      }
    },
    onStreamHealth: {
      subscribe: (params: undefined, handlers: { onData: (data: any) => void }): Subscription => {
        try {
          return (
            (trpc as any).monitoring?.performance?.onStreamHealth?.subscribe?.(params, handlers) ?? {
              unsubscribe: () => {}
            }
          )
        } catch {
          return { unsubscribe: () => {} }
        }
      }
    }
  }
}
