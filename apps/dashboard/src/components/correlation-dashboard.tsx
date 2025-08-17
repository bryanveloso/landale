/**
 * Correlation Dashboard Component
 *
 * Main dashboard panel that combines all correlation-related components.
 * Provides a comprehensive view of the correlation engine status and insights.
 */

import { Show, createSignal } from 'solid-js'
import { CorrelationInsights } from './correlation-insights'
import { CorrelationPatterns } from './correlation-patterns'
import { CorrelationFeed } from './correlation-feed'
import { CorrelationMetrics } from './correlation-metrics'

export function CorrelationDashboard() {
  const [activeTab, setActiveTab] = createSignal<'insights' | 'patterns' | 'feed' | 'metrics'>('insights')

  const tabs = [
    { id: 'insights' as const, name: 'Insights', icon: '💡' },
    { id: 'patterns' as const, name: 'Patterns', icon: '📊' },
    { id: 'feed' as const, name: 'Live Feed', icon: '📡' },
    { id: 'metrics' as const, name: 'Metrics', icon: '⚡' }
  ]

  return (
    <div class="flex h-full min-w-80 flex-col border-r border-gray-800 bg-gray-900">
      {/* Header */}
      <div class="border-b border-gray-800 bg-gray-900 p-3">
        <h2 class="mb-2 text-sm font-medium text-gray-200">Correlation Engine</h2>

        {/* Tab Navigation */}
        <div class="flex gap-1">
          {tabs.map((tab) => (
            <button
              class={`flex items-center gap-1 rounded px-2 py-1 text-xs transition-colors ${
                activeTab() === tab.id ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
              onClick={() => setActiveTab(tab.id)}>
              <span>{tab.icon}</span>
              <span>{tab.name}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Content */}
      <div class="flex-1 overflow-hidden">
        <Show when={activeTab() === 'insights'}>
          <CorrelationInsights />
        </Show>

        <Show when={activeTab() === 'patterns'}>
          <CorrelationPatterns />
        </Show>

        <Show when={activeTab() === 'feed'}>
          <CorrelationFeed />
        </Show>

        <Show when={activeTab() === 'metrics'}>
          <CorrelationMetrics />
        </Show>
      </div>
    </div>
  )
}
