import { Show } from 'solid-js'

export interface LayerRendererProps {
  content: unknown
  contentType: string
  show?: string
}

export function LayerRenderer(props: LayerRendererProps) {
  return (
    <Show when={props.content}>
      <div class="content-renderer" data-content={props.contentType} data-show-context={props.show}>
        <ContentComponent type={props.contentType} data={props.content} show={props.show} />
      </div>
    </Show>
  )
}

// Dynamic content component router
function ContentComponent(props: { type: string; data: unknown; show?: string }) {
  switch (props.type) {
    // Foreground alerts
    case 'alert':
      return <AlertContent data={props.data} show={props.show} />

    case 'sub_train':
      return <SubTrainContent data={props.data} show={props.show} />

    // Background ticker content
    case 'emote_stats':
      return <EmoteStatsContent data={props.data} show={props.show} />

    case 'recent_follows':
      return <RecentFollowsContent data={props.data} show={props.show} />

    case 'daily_stats':
      return <DailyStatsContent data={props.data} show={props.show} />

    case 'stream_goals':
      return <StreamGoalsContent data={props.data} show={props.show} />

    // Ironmon-specific content
    case 'ironmon_run_stats':
      return <IronmonRunStatsContent data={props.data} show={props.show} />

    case 'ironmon_progression':
      return <IronmonProgressionContent data={props.data} show={props.show} />

    // Midground events timeline
    case 'events_timeline':
      return <EventsTimelineContent data={props.data} show={props.show} />

    // Latest event (base layer)
    case 'latest_event':
      return <LatestEventContent data={props.data} show={props.show} />

    // Individual events (now used for background)
    case 'channel.follow':
      return <FollowEventContent data={props.data} show={props.show} />

    case 'channel.subscribe':
      return <SubscribeEventContent data={props.data} show={props.show} />

    case 'channel.subscription.gift':
      return <GiftSubEventContent data={props.data} show={props.show} />

    default:
      return <DefaultContent type={props.type} data={props.data} show={props.show} />
  }
}

// Content Components - minimal markup with data attributes for styling
function AlertContent(props: { data: unknown; show?: string }) {
  return (
    <div class="content-alert">
      <div class="alert-message">{props.data?.message || 'Breaking News'}</div>
    </div>
  )
}

function SubTrainContent(props: { data: unknown; show?: string }) {
  return (
    <div class="content-sub-train">
      <div class="train-count">{props.data?.count || 1}</div>
      <div class="train-subscriber">{props.data?.latest_subscriber || props.data?.subscriber || 'Unknown'}</div>
      <div class="train-tier">{props.data?.latest_tier || props.data?.tier || '1000'}</div>
    </div>
  )
}

function EmoteStatsContent(props: { data: unknown; show?: string }) {
  const emotes = () => props.data?.regular_emotes || props.data?.emotes || {}
  const topEmotes = () => Object.entries(emotes()).slice(0, 3)

  return (
    <div class="content-emote-stats">
      <div class="emote-list">
        {topEmotes().map(([emote, count]) => (
          <div class="emote">
            <span class="emote-name">{emote}</span>
            <span class="emote-count">{count as number}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function RecentFollowsContent(props: { data: unknown; show?: string }) {
  const followers = () => props.data?.recent_followers || []

  return (
    <div class="content-recent-follows">
      <div class="follows-label">Latest Follows</div>
      <div class="followers-list">
        {followers()
          .slice(0, 3)
          .map((follower: string) => (
            <div class="follower-name">{follower}</div>
          ))}
      </div>
    </div>
  )
}

function IronmonRunStatsContent(props: { data: unknown; show?: string }) {
  return (
    <div class="content-ironmon-run-stats">
      <div class="run-header">
        <span class="run-label">Run</span>
        <span class="run-number">#{props.data?.run_number || '?'}</span>
      </div>
      <div class="progress-info">
        <div class="checkpoints">
          <span class="cleared">{props.data?.checkpoints_cleared || 0}</span>
          <span class="separator">/</span>
          <span class="total">{props.data?.total_checkpoints || 8}</span>
        </div>
        <div class="progress-percentage">{props.data?.progress_percentage || 0}%</div>
      </div>
      <div class="current-location">{props.data?.current_checkpoint || 'Unknown'}</div>
    </div>
  )
}

function IronmonProgressionContent(props: { data: unknown; show?: string }) {
  return (
    <div class="content-ironmon-progression">
      {props.data?.has_active_run ? (
        <>
          <div class="trainer-name">{props.data?.trainer || 'Unknown Trainer'}</div>
          <div class="clear-rate">{props.data?.clear_rate || 0}% Clear Rate</div>
          <div class="location">{props.data?.location || 'Unknown Location'}</div>
        </>
      ) : (
        <div class="no-run-message">{props.data?.message || 'No active IronMON run'}</div>
      )}
    </div>
  )
}

function DailyStatsContent(props: { data: unknown; show?: string }) {
  return (
    <div class="content-daily-stats">
      <div class="stats-grid">
        <div class="stat-item">
          <span class="stat-value">{props.data?.total_messages || 0}</span>
          <span class="stat-label">Messages</span>
        </div>
        <div class="stat-item">
          <span class="stat-value">{props.data?.total_follows || 0}</span>
          <span class="stat-label">Follows</span>
        </div>
      </div>
    </div>
  )
}

function StreamGoalsContent(props: { data: unknown; show?: string }) {
  const followerGoal = () => props.data?.follower_goal || { current: 0, target: 0 }
  const subGoal = () => props.data?.sub_goal || { current: 0, target: 0 }

  return (
    <div class="content-stream-goals">
      <div class="goals-header">Stream Goals</div>
      <div class="goals-grid">
        <div class="goal-item">
          <div class="goal-label">Followers</div>
          <div class="goal-progress">
            <span class="goal-current">{followerGoal().current}</span>
            <span class="goal-separator">/</span>
            <span class="goal-target">{followerGoal().target}</span>
          </div>
        </div>
        <div class="goal-item">
          <div class="goal-label">Subs</div>
          <div class="goal-progress">
            <span class="goal-current">{subGoal().current}</span>
            <span class="goal-separator">/</span>
            <span class="goal-target">{subGoal().target}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

// Latest event component for base layer
function LatestEventContent(props: { data: unknown; show?: string }) {
  const eventData = props.data as {
    type?: string
    user_name?: string
    followed_at?: string
    tier?: string
    is_gift?: boolean
    recipient_user_name?: string
    total?: number
    message?: string
  }

  if (!eventData || typeof eventData !== 'object') {
    return (
      <div class="content-latest-event">
        <div class="no-event">No recent events</div>
      </div>
    )
  }

  return (
    <div class="content-latest-event">
      <div class="event-label">Latest Event</div>
      <div class="event-content">{renderLatestEventByType(eventData)}</div>
      <div class="event-timestamp">{formatTimestamp(eventData.followed_at)}</div>
    </div>
  )
}

function renderLatestEventByType(eventData: {
  type?: string
  user_name?: string
  tier?: string
  recipient_user_name?: string
  total?: number
  message?: string
}) {
  switch (eventData.type) {
    case 'channel.follow':
      return (
        <>
          <div class="event-icon">👋</div>
          <div class="event-text">
            <span class="username">{eventData.user_name}</span> followed
          </div>
        </>
      )

    case 'channel.subscribe': {
      const tier = eventData.tier === '1000' ? 'T1' : eventData.tier === '2000' ? 'T2' : 'T3'
      return (
        <>
          <div class="event-icon">⭐</div>
          <div class="event-text">
            <span class="username">{eventData.user_name}</span> subscribed ({tier})
          </div>
        </>
      )
    }

    case 'channel.subscription.gift':
      return (
        <>
          <div class="event-icon">🎁</div>
          <div class="event-text">
            <span class="username">{eventData.user_name}</span> gifted to{' '}
            <span class="username">{eventData.recipient_user_name}</span>
          </div>
        </>
      )

    case 'channel.cheer':
      return (
        <>
          <div class="event-icon">💎</div>
          <div class="event-text">
            <span class="username">{eventData.user_name}</span> cheered {eventData.total} bits
          </div>
        </>
      )

    default:
      return (
        <>
          <div class="event-icon">📝</div>
          <div class="event-text">{eventData.message || `${eventData.type} event`}</div>
        </>
      )
  }
}

// Events timeline component for midground layer
function EventsTimelineContent(props: { data: unknown; show?: string }) {
  const timelineData = props.data as {
    events?: Array<{
      type: string
      user_name?: string
      tier?: string
      total?: number
      followed_at?: string
      recipient_user_name?: string
    }>
  }
  const events = timelineData.events || []

  return (
    <div class="content-events-timeline">
      <div class="timeline-container">
        {events.slice(0, 6).map((event) => (
          <div class="timeline-event">
            <EventTimelineItem event={event} />
          </div>
        ))}
      </div>
    </div>
  )
}

function EventTimelineItem(props: {
  event: {
    type: string
    user_name?: string
    tier?: string
    recipient_user_name?: string
  }
}) {
  const { event } = props

  switch (event.type) {
    case 'channel.follow':
      return (
        <div class="timeline-item-follow">
          <span class="timeline-icon">👋</span>
          <span class="timeline-text">{event.user_name}</span>
        </div>
      )

    case 'channel.subscribe': {
      const tier = event.tier === '1000' ? '1' : event.tier === '2000' ? '2' : '3'
      return (
        <div class="timeline-item-sub">
          <span class="timeline-icon">⭐</span>
          <span class="timeline-text">
            {event.user_name} T{tier}
          </span>
        </div>
      )
    }

    case 'channel.subscription.gift':
      return (
        <div class="timeline-item-gift">
          <span class="timeline-icon">🎁</span>
          <span class="timeline-text">
            {event.user_name} → {event.recipient_user_name}
          </span>
        </div>
      )

    default:
      return (
        <div class="timeline-item-default">
          <span class="timeline-text">{event.type}</span>
        </div>
      )
  }
}

// Event content components for individual events (background layer)
function FollowEventContent(props: { data: unknown; show?: string }) {
  const followData = props.data as { user_name?: string; followed_at?: string }
  return (
    <div class="content-follow-event">
      <div class="event-icon">👋</div>
      <div class="event-message">
        <span class="follower-name">{followData.user_name || 'Someone'}</span>
        <span class="event-text">followed!</span>
      </div>
      <div class="event-timestamp">{formatTimestamp(followData.followed_at)}</div>
    </div>
  )
}

function SubscribeEventContent(props: { data: unknown; show?: string }) {
  const subData = props.data as { user_name?: string; tier?: string; is_gift?: boolean }
  const tier = () => {
    const tierValue = subData.tier || '1000'
    return tierValue === '1000' ? 'Tier 1' : tierValue === '2000' ? 'Tier 2' : 'Tier 3'
  }

  return (
    <div class="content-subscribe-event">
      <div class="event-icon">⭐</div>
      <div class="event-message">
        <span class="subscriber-name">{subData.user_name || 'Someone'}</span>
        <span class="event-text">subscribed!</span>
        <span class="subscription-tier">{tier()}</span>
      </div>
      {subData.is_gift && <div class="gift-indicator">Gift Sub</div>}
    </div>
  )
}

function GiftSubEventContent(props: { data: unknown; show?: string }) {
  const giftData = props.data as { user_name?: string; recipient_user_name?: string; total?: number }
  return (
    <div class="content-gift-sub-event">
      <div class="event-icon">🎁</div>
      <div class="event-message">
        <span class="gifter-name">{giftData.user_name || 'Someone'}</span>
        <span class="event-text">gifted a sub to</span>
        <span class="recipient-name">{giftData.recipient_user_name || 'someone'}</span>
      </div>
      <div class="gift-count">
        {giftData.total || 1} gift{(giftData.total || 1) > 1 ? 's' : ''}
      </div>
    </div>
  )
}

function DefaultContent(props: { type: string; data: unknown; show?: string }) {
  return (
    <div class="content-default">
      <div class="content-type">{props.type.replace(/_/g, ' ')}</div>
      <div class="content-data">{JSON.stringify(props.data, null, 2)}</div>
    </div>
  )
}

// Helper function for timestamp formatting
function formatTimestamp(timestamp?: string) {
  if (!timestamp) return ''
  try {
    return new Date(timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  } catch {
    return ''
  }
}
