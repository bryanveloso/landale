import { useState, useEffect } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { FileText, CheckCircle, XCircle } from 'lucide-react'
import { monitoringTrpc } from '@/lib/monitoring-trpc'
import { formatDistanceToNow } from 'date-fns'

interface AuditEvent {
  id: string
  timestamp: Date
  action: string
  category: string
  result: 'success' | 'failure'
  error?: string
  resource?: {
    type: string
    name?: string
    id?: string
  }
  changes?: {
    before?: unknown
    after?: unknown
  }
  metadata?: Record<string, unknown>
  correlationId?: string
}

const categoryColors: Record<string, string> = {
  stream: 'bg-purple-500',
  config: 'bg-blue-500',
  scene: 'bg-green-500',
  connection: 'bg-yellow-500',
  recording: 'bg-red-500',
  service: 'bg-gray-500',
  security: 'bg-orange-500',
  performance: 'bg-pink-500'
}

const actionLabels: Record<string, string> = {
  'stream.start': 'Stream Started',
  'stream.stop': 'Stream Stopped',
  'stream.health.critical': 'Stream Health Critical',
  'config.update': 'Configuration Updated',
  'scene.change': 'Scene Changed',
  'connection.established': 'Connection Established',
  'connection.lost': 'Connection Lost',
  'connection.failed': 'Connection Failed',
  'recording.start': 'Recording Started',
  'recording.stop': 'Recording Stopped',
  'service.start': 'Service Started',
  'service.stop': 'Service Stopped',
  'auth.failure': 'Authentication Failed',
  'performance.critical': 'Performance Critical'
}

export function AuditLogPanel() {
  const [events, setEvents] = useState<AuditEvent[]>([])
  const [categoryFilter, setCategoryFilter] = useState<string>('all')
  const [liveEvents, setLiveEvents] = useState<AuditEvent[]>([])

  // Query recent events
  const queryResult = monitoringTrpc.audit.getRecentEvents.useQuery({
    limit: 100,
    category: categoryFilter === 'all' ? undefined : categoryFilter
  })
  const recentEvents = queryResult.data as AuditEvent[] | undefined

  // Subscribe to live events
  useEffect(() => {
    const sub = monitoringTrpc.audit.onEvents.subscribe(undefined, {
      onData: (event: AuditEvent) => {
        setLiveEvents((prev) => [event, ...prev.slice(0, 49)])
      }
    })

    return () => {
      sub.unsubscribe()
    }
  }, [])

  // Combine and deduplicate events
  useEffect(() => {
    const allEvents = [...liveEvents, ...(recentEvents ?? [])]
    const uniqueEvents = Array.from(new Map(allEvents.map((e) => [e.id, e])).values()).sort(
      (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
    )

    setEvents(uniqueEvents.slice(0, 100))
  }, [recentEvents, liveEvents])

  const getActionLabel = (action: string) => actionLabels[action] || action

  const formatMetadata = (metadata: Record<string, unknown> | undefined) => {
    if (!metadata) return null

    const relevant = Object.entries(metadata)
      .filter(([key]) => !['timestamp', 'id'].includes(key))
      .slice(0, 3)

    if (relevant.length === 0) return null

    return relevant
      .map(
        ([key, value]) =>
          `${key}: ${typeof value === 'object' && value !== null ? JSON.stringify(value) : String(value)}`
      )
      .join(', ')
  }

  return (
    <Card className="h-full">
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <FileText className="h-5 w-5" />
              Audit Log
            </CardTitle>
            <CardDescription>System activity and events</CardDescription>
          </div>

          <Select
            value={categoryFilter}
            onChange={(e) => {
              setCategoryFilter(e.target.value)
            }}>
            <SelectTrigger className="w-[180px]">
              <SelectValue placeholder="Filter by category" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Categories</SelectItem>
              <SelectItem value="stream">Stream</SelectItem>
              <SelectItem value="config">Configuration</SelectItem>
              <SelectItem value="scene">Scene</SelectItem>
              <SelectItem value="connection">Connection</SelectItem>
              <SelectItem value="recording">Recording</SelectItem>
              <SelectItem value="service">Service</SelectItem>
              <SelectItem value="security">Security</SelectItem>
              <SelectItem value="performance">Performance</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </CardHeader>

      <CardContent>
        <ScrollArea className="h-[600px]">
          <div className="space-y-2">
            {events.map((event) => (
              <div
                key={event.id}
                className={`rounded-lg border p-3 ${
                  event.result === 'failure' ? 'border-red-500/50 bg-red-50/10' : 'border-border'
                }`}>
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1">
                    <div className="mb-1 flex items-center gap-2">
                      {event.result === 'success' ? (
                        <CheckCircle className="h-4 w-4 text-green-600" />
                      ) : (
                        <XCircle className="h-4 w-4 text-red-600" />
                      )}

                      <span className="text-sm font-medium">{getActionLabel(event.action)}</span>

                      <Badge
                        variant="secondary"
                        className={`${categoryColors[event.category] ?? ''} text-xs text-white`}>
                        {event.category}
                      </Badge>
                    </div>

                    {event.resource && (
                      <div className="text-muted-foreground mb-1 text-xs">
                        {event.resource.type}: {event.resource.name ?? event.resource.id ?? ''}
                      </div>
                    )}

                    {event.error && <div className="mb-1 text-xs text-red-600">Error: {event.error}</div>}

                    {event.changes && (event.changes.before !== undefined || event.changes.after !== undefined) && (
                      <div className="text-muted-foreground text-xs">
                        {event.changes.before !== undefined && (
                          <span>From: {String(JSON.stringify(event.changes.before))}</span>
                        )}
                        {event.changes.before !== undefined && event.changes.after !== undefined && (
                          <span> → </span>
                        )}
                        {event.changes.after !== undefined && (
                          <span>To: {String(JSON.stringify(event.changes.after))}</span>
                        )}
                      </div>
                    )}

                    {event.metadata && (
                      <div className="text-muted-foreground mt-1 text-xs">{formatMetadata(event.metadata)}</div>
                    )}
                  </div>

                  <div className="text-muted-foreground text-xs whitespace-nowrap">
                    {formatDistanceToNow(new Date(event.timestamp), { addSuffix: true })}
                  </div>
                </div>

                {event.correlationId && (
                  <div className="text-muted-foreground mt-1 text-xs">ID: {event.correlationId}</div>
                )}
              </div>
            ))}

            {events.length === 0 && <div className="text-muted-foreground py-8 text-center">No audit events found</div>}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  )
}
