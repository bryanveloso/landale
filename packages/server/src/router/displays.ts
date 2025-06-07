import { z } from 'zod'
import { router, publicProcedure } from '@/trpc'
import { TRPCError } from '@trpc/server'
import { displayManager } from '@/services/display-manager'
import { createEventSubscription } from '@/lib/subscription'

export const displaysRouter = router({
  /**
   * List all registered displays
   */
  list: publicProcedure.query(() => {
    return displayManager.list().map(display => ({
      id: display.id,
      isVisible: display.isVisible,
      metadata: display.metadata,
      lastUpdated: display.lastUpdated
    }))
  }),
  
  /**
   * Get specific display
   */
  get: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(({ input }) => {
      const display = displayManager.get(input.id)
      if (!display) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: `Display ${input.id} not found`
        })
      }
      return display
    }),
  
  /**
   * Update display data
   */
  update: publicProcedure
    .input(z.object({
      id: z.string(),
      data: z.any()
    }))
    .mutation(({ input }) => {
      try {
        return displayManager.update(input.id, input.data)
      } catch (error) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: error instanceof Error ? error.message : 'Failed to update display'
        })
      }
    }),
  
  /**
   * Update display visibility
   */
  setVisibility: publicProcedure
    .input(z.object({
      id: z.string(),
      isVisible: z.boolean()
    }))
    .mutation(({ input }) => {
      try {
        return displayManager.setVisibility(input.id, input.isVisible)
      } catch (error) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: error instanceof Error ? error.message : 'Failed to update visibility'
        })
      }
    }),
  
  /**
   * Clear display data
   */
  clear: publicProcedure
    .input(z.object({ id: z.string() }))
    .mutation(({ input }) => {
      try {
        displayManager.clear(input.id)
        return { success: true }
      } catch (error) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: error instanceof Error ? error.message : 'Failed to clear display'
        })
      }
    }),
  
  /**
   * Subscribe to display updates
   */
  subscribe: publicProcedure
    .input(z.object({ id: z.string() }))
    .subscription(async function* (opts) {
      const { input } = opts
      
      // Send initial state
      const display = displayManager.get(input.id)
      if (!display) {
        throw new TRPCError({
          code: 'NOT_FOUND',
          message: `Display ${input.id} not found`
        })
      }
      yield display
      
      // Stream updates
      yield* createEventSubscription(opts, {
        events: [`display:${input.id}:update` as any],
        onError: (_error) =>
          new TRPCError({
            code: 'INTERNAL_SERVER_ERROR',
            message: `Failed to stream updates for display ${input.id}`
          })
      })
    }),
  
  /**
   * Subscribe to all display updates
   */
  subscribeAll: publicProcedure.subscription(async function* (opts) {
    // Send initial state of all displays
    yield displayManager.list()
    
    // Stream all display updates
    const displayIds = displayManager.list().map(d => d.id)
    const events = displayIds.map(id => `display:${id}:update` as any)
    
    yield* createEventSubscription(opts, {
      events,
      transform: (_event, data) => data,
      onError: (_error) =>
        new TRPCError({
          code: 'INTERNAL_SERVER_ERROR',
          message: 'Failed to stream display updates'
        })
    })
  })
})