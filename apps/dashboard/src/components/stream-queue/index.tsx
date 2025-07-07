import { createSignal, createEffect, Show, For } from 'solid-js'
import { useStreamQueue } from '../../hooks/use-stream-queue'

export function StreamQueue() {
  const { queueState, isConnected, clearQueue, removeQueueItem, reorderQueue } = useStreamQueue()
  const [isVisible, setIsVisible] = createSignal(true)

  return (
    <Show when={isVisible()}>
      <div
        data-stream-queue
        data-connected={isConnected()}
        data-processing={queueState().is_processing}
        data-queue-size={queueState().queue.length}>
        
        {/* Queue header with controls */}
        <div data-queue-header>
          <div data-queue-title>Stream Queue</div>
          <div data-queue-controls>
            <button 
              data-queue-action="clear"
              onclick={() => clearQueue()}
              disabled={queueState().queue.length === 0}>
              Clear Queue
            </button>
          </div>
        </div>

        {/* Queue metrics */}
        <div data-queue-metrics>
          <div data-metric="total" data-value={queueState().metrics.total_items}>
            Total: {queueState().metrics.total_items}
          </div>
          <div data-metric="pending" data-value={queueState().metrics.pending_items}>
            Pending: {queueState().metrics.pending_items}
          </div>
          <div data-metric="active" data-value={queueState().metrics.active_items}>
            Active: {queueState().metrics.active_items}
          </div>
          <div data-metric="wait-time" data-value={queueState().metrics.average_wait_time}>
            Avg Wait: {Math.round(queueState().metrics.average_wait_time / 1000)}s
          </div>
        </div>

        {/* Active content display */}
        <Show when={queueState().active_content}>
          <div data-active-content>
            <div data-active-header>Currently Active</div>
            <div data-active-item
                 data-type={queueState().active_content?.type}
                 data-priority={queueState().active_content?.priority}>
              <div data-item-type>{queueState().active_content?.type}</div>
              <div data-item-id>{queueState().active_content?.id}</div>
              <div data-item-duration>{queueState().active_content?.duration}ms</div>
            </div>
          </div>
        </Show>

        {/* Queue items list */}
        <div data-queue-list>
          <For each={queueState().queue}>
            {(item, index) => (
              <div data-queue-item
                   data-type={item.type}
                   data-status={item.status}
                   data-priority={item.priority}
                   data-position={index()}>
                
                <div data-item-header>
                  <div data-item-type>{item.type}</div>
                  <div data-item-status>{item.status}</div>
                  <div data-item-priority>{item.priority}</div>
                </div>
                
                <div data-item-content>
                  <div data-item-id>{item.id}</div>
                  <Show when={item.duration}>
                    <div data-item-duration>{item.duration}ms</div>
                  </Show>
                  <Show when={item.started_at}>
                    <div data-item-started>{new Date(item.started_at!).toLocaleTimeString()}</div>
                  </Show>
                </div>
                
                <div data-item-controls>
                  <button 
                    data-item-action="remove"
                    onclick={() => removeQueueItem(item.id)}>
                    Remove
                  </button>
                </div>
              </div>
            )}
          </For>
        </div>

        {/* Empty state */}
        <Show when={queueState().queue.length === 0}>
          <div data-queue-empty>
            <div data-empty-message>No items in queue</div>
          </div>
        </Show>

        {/* Debug info - you can style or remove this */}
        {import.meta.env.DEV && (
          <div data-queue-debug>
            <div>Connected: {isConnected() ? '✓' : '✗'}</div>
            <div>Processing: {queueState().is_processing ? 'Yes' : 'No'}</div>
            <div>Queue Size: {queueState().queue.length}</div>
            <div>Last Processed: {queueState().metrics.last_processed || 'Never'}</div>
          </div>
        )}
      </div>
    </Show>
  )
}