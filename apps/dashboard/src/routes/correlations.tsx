import { createFileRoute } from '@tanstack/solid-router'
import { CorrelationDashboard } from '@/components/correlation-dashboard'
import { CorrelationInsights } from '@/components/correlation-insights'
import { CorrelationPatterns } from '@/components/correlation-patterns'
import { CorrelationFeed } from '@/components/correlation-feed'
import { CorrelationMetrics } from '@/components/correlation-metrics'
import { StatusBar } from '@/components/status-bar'
import { ConnectionMonitor } from '@/components/error-boundary'

export const Route = createFileRoute('/correlations')({
  component: Correlations
})

function Correlations() {
  return (
    <ConnectionMonitor>
      <div class="grid h-full grid-rows-[1fr_auto]" data-dashboard-layout>
        {/* Full-page correlation view with all components */}
        <div class="grid grid-cols-1 gap-4 overflow-auto bg-gray-900 p-4 lg:grid-cols-2 xl:grid-cols-3">
          {/* Main insights */}
          <div class="lg:col-span-2 xl:col-span-2">
            <div class="bg-gray-850 rounded-lg border border-gray-800">
              <CorrelationInsights />
            </div>
          </div>

          {/* Metrics sidebar */}
          <div class="space-y-4">
            <div class="bg-gray-850 rounded-lg border border-gray-800">
              <CorrelationMetrics />
            </div>
            <div class="bg-gray-850 rounded-lg border border-gray-800">
              <CorrelationPatterns />
            </div>
          </div>

          {/* Live feed full width */}
          <div class="lg:col-span-2 xl:col-span-3">
            <div class="bg-gray-850 rounded-lg border border-gray-800">
              <CorrelationFeed />
            </div>
          </div>
        </div>

        <StatusBar />
      </div>
    </ConnectionMonitor>
  )
}
