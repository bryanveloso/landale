import { createSignal, createEffect, Show, For } from 'solid-js'
import { useStreamQueue } from '@/hooks/use-stream-queue'
import { Button } from './ui/button'

export function StreamQueue() {
  const { queueState, isConnected, clearQueue, removeQueueItem, reorderQueue } = useStreamQueue()
  const [isVisible, setIsVisible] = createSignal(true)

  return (
    <Show when={isVisible()}>
      <div>
        {/* Queue header with controls */}
        <div>
          <div>Stream Queue</div>
          <div>
            <Button onClick={() => clearQueue()} disabled={queueState().queue.length === 0}>
              Clear Queue
            </Button>
          </div>
        </div>

        {/* Queue metrics */}
        <div>
          <div>Total: {queueState().metrics.total_items}</div>
          <div>Pending: {queueState().metrics.pending_items}</div>
          <div>Active: {queueState().metrics.active_items}</div>
          <div>Avg Wait: {Math.round(queueState().metrics.average_wait_time / 1000)}s</div>
        </div>

        {/* Active content display */}
        <Show when={queueState().active_content}>
          <div>
            <div>Currently Active</div>
            <div>
              <div>{queueState().active_content?.type}</div>
              <div>{queueState().active_content?.id}</div>
              <div>{queueState().active_content?.duration}ms</div>
            </div>
          </div>
        </Show>

        {/* Queue items list */}
        <div>
          <For each={queueState().queue}>
            {(item, index) => (
              <div>
                <div>
                  <div>{item.type}</div>
                  <div>{item.status}</div>
                  <div>{item.priority}</div>
                </div>

                <div>
                  <div>{item.id}</div>
                  <Show when={item.duration}>
                    <div>{item.duration}ms</div>
                  </Show>
                  <Show when={item.started_at}>
                    <div>{new Date(item.started_at!).toLocaleTimeString()}</div>
                  </Show>
                </div>

                <div>
                  <Button onClick={() => removeQueueItem(item.id)}>Remove</Button>
                </div>
              </div>
            )}
          </For>
        </div>

        {/* Empty state */}
        <Show when={queueState().queue.length === 0}>
          <div>
            <div>No items in queue</div>
          </div>
        </Show>

        {/* Debug info */}
        {import.meta.env.DEV && (
          <div>
            <div>Processing: {queueState().is_processing ? 'Yes' : 'No'}</div>
            <div>Queue Size: {queueState().queue.length}</div>
            <div>Last Processed: {queueState().metrics.last_processed || 'Never'}</div>
          </div>
        )}
      </div>
    </Show>
  )
}
