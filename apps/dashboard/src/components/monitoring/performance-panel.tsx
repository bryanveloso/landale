import { useState, useEffect } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { AlertCircle, Activity, Zap } from 'lucide-react'
import { monitoringTrpc } from '@/lib/monitoring-trpc'

interface PerformanceMetric {
  operation: string
  duration: number
  success: boolean
  metadata?: Record<string, unknown>
  timestamp: Date
  correlationId?: string
}

interface StreamHealthData {
  fps: number
  bitrate: number
  droppedFrames: number
  totalFrames: number
  cpuUsage: number
  memoryUsage: number
  congestion: number
  timestamp: Date
  alerts?: string[]
}

export function PerformancePanel() {
  const [recentMetrics, setRecentMetrics] = useState<PerformanceMetric[]>([])
  const [streamHealth, setStreamHealth] = useState<StreamHealthData | null>(null)
  const [activeAlerts, setActiveAlerts] = useState<string[]>([])
  const MAX_METRICS = 100 // Prevent unbounded growth

  useEffect(() => {
    // Subscribe to performance metrics
    const metricsSub = monitoringTrpc.performance.onMetrics.subscribe(undefined, {
      onData: (data: PerformanceMetric) => {
        setRecentMetrics((prev) => [...prev.slice(-MAX_METRICS + 1), data])
      }
    })

    // Subscribe to stream health
    const healthSub = monitoringTrpc.performance.onStreamHealth.subscribe(undefined, {
      onData: (data: StreamHealthData & { alerts?: string[] }) => {
        if (data.alerts) {
          // This is a health alert
          setActiveAlerts(data.alerts)
        } else {
          // This is a health metric
          setStreamHealth(data)
          // Clear alerts if health is good
          if (data.fps >= 25 && data.cpuUsage < 70) {
            setActiveAlerts([])
          }
        }
      }
    })

    return () => {
      metricsSub.unsubscribe()
      healthSub.unsubscribe()
    }
  }, [])

  // Calculate average operation times
  const operationStats = recentMetrics.reduce<Record<string, { total: number; count: number; max: number }>>(
    (acc, metric) => {
      const m = metric as { operation: string; duration: number }
      if (!acc[m.operation]) {
        acc[m.operation] = { total: 0, count: 0, max: 0 }
      }

      const stat = acc[m.operation]
      if (stat) {
        stat.total += m.duration
        stat.count += 1
        stat.max = Math.max(stat.max, m.duration)
      }

      return acc
    },
    {}
  )

  const getHealthColor = (value: number, thresholds: { warning: number; critical: number }, inverse = false) => {
    if (inverse) {
      if (value <= thresholds.critical) return 'text-green-600'
      if (value <= thresholds.warning) return 'text-yellow-600'
      return 'text-red-600'
    } else {
      if (value >= thresholds.critical) return 'text-red-600'
      if (value >= thresholds.warning) return 'text-yellow-600'
      return 'text-green-600'
    }
  }

  return (
    <div className="space-y-4">
      {/* Active Alerts */}
      {activeAlerts.length > 0 && (
        <Alert variant="destructive">
          <AlertCircle className="h-4 w-4" />
          <AlertTitle>Stream Health Alert</AlertTitle>
          <AlertDescription>
            <ul className="list-inside list-disc">
              {activeAlerts.map((alert, i) => (
                <li key={i}>{alert}</li>
              ))}
            </ul>
          </AlertDescription>
        </Alert>
      )}

      {/* Stream Health */}
      {streamHealth && 'fps' in streamHealth && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Activity className="h-5 w-5" />
              Stream Health
            </CardTitle>
            <CardDescription>Real-time streaming performance metrics</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
              <div>
                <p className="text-muted-foreground text-sm">FPS</p>
                <p
                  className={`text-2xl font-bold ${getHealthColor(streamHealth.fps, { warning: 25, critical: 20 }, true)}`}>
                  {streamHealth.fps.toFixed(1)}
                </p>
              </div>

              <div>
                <p className="text-muted-foreground text-sm">CPU Usage</p>
                <p
                  className={`text-2xl font-bold ${getHealthColor(streamHealth.cpuUsage, { warning: 70, critical: 85 })}`}>
                  {streamHealth.cpuUsage.toFixed(1)}%
                </p>
              </div>

              <div>
                <p className="text-muted-foreground text-sm">Dropped Frames</p>
                <p
                  className={`text-2xl font-bold ${
                    streamHealth.totalFrames > 0
                      ? getHealthColor((streamHealth.droppedFrames / streamHealth.totalFrames) * 100, {
                          warning: 0.5,
                          critical: 2
                        })
                      : 'text-muted-foreground'
                  }`}>
                  {streamHealth.droppedFrames} / {streamHealth.totalFrames}
                </p>
              </div>

              <div>
                <p className="text-muted-foreground text-sm">Memory</p>
                <p className="text-2xl font-bold">{streamHealth.memoryUsage.toFixed(1)} MB</p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Operation Performance */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Zap className="h-5 w-5" />
            Operation Performance
          </CardTitle>
          <CardDescription>Average response times for recent operations</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            {Object.entries(operationStats).map(([operation, stats]) => {
              const avg =
                (stats as { total: number; count: number; max: number }).total /
                (stats as { total: number; count: number }).count
              const color = avg > 500 ? 'text-red-600' : avg > 100 ? 'text-yellow-600' : 'text-green-600'

              return (
                <div key={operation} className="flex items-center justify-between py-1">
                  <span className="text-sm font-medium">{operation}</span>
                  <div className="flex gap-4 text-sm">
                    <span className={color}>avg: {avg.toFixed(1)}ms</span>
                    <span className="text-muted-foreground">max: {(stats as { max: number }).max.toFixed(1)}ms</span>
                    <span className="text-muted-foreground">({(stats as { count: number }).count} calls)</span>
                  </div>
                </div>
              )
            })}

            {Object.keys(operationStats).length === 0 && (
              <p className="text-muted-foreground py-4 text-center text-sm">No recent operations recorded</p>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
