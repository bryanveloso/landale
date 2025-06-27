'use client'

import { PerformancePanel } from '@/components/monitoring/performance-panel'
import { AuditLogPanel } from '@/components/monitoring/audit-log-panel'
import { MonitoringErrorBoundary } from '@/components/monitoring/error-boundary'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'

export default function MonitoringPage() {
  return (
    <div className="container mx-auto py-6">
      <div className="mb-6">
        <h1 className="text-3xl font-bold">System Monitoring</h1>
        <p className="text-muted-foreground">Real-time performance metrics and audit logs for your streaming system</p>
      </div>

      <Tabs defaultValue="performance" className="space-y-4">
        <TabsList>
          <TabsTrigger value="performance">Performance</TabsTrigger>
          <TabsTrigger value="audit">Audit Log</TabsTrigger>
        </TabsList>

        <TabsContent value="performance" className="space-y-4">
          <MonitoringErrorBoundary>
            <PerformancePanel />
          </MonitoringErrorBoundary>
        </TabsContent>

        <TabsContent value="audit">
          <MonitoringErrorBoundary>
            <AuditLogPanel />
          </MonitoringErrorBoundary>
        </TabsContent>
      </Tabs>
    </div>
  )
}
