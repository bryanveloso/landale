import { Show } from 'solid-js'

export interface LayerRendererProps {
  content: any
  contentType: string
  show?: string
}

export function LayerRenderer(props: LayerRendererProps) {
  return (
    <Show when={props.content}>
      <div 
        class="content-renderer"
        data-content={props.contentType}
        data-show-context={props.show}
      >
        <ContentComponent 
          type={props.contentType} 
          data={props.content} 
          show={props.show}
        />
      </div>
    </Show>
  )
}

// Dynamic content component router
function ContentComponent(props: { type: string; data: any; show?: string }) {
  switch (props.type) {
    case 'alert':
      return <AlertContent data={props.data} show={props.show} />
    
    case 'sub_train':
      return <SubTrainContent data={props.data} show={props.show} />
    
    case 'emote_stats':
      return <EmoteStatsContent data={props.data} show={props.show} />
    
    case 'recent_follows':
      return <FollowsContent data={props.data} show={props.show} />
    
    case 'ironmon_run_stats':
      return <IronmonStatsContent data={props.data} show={props.show} />
    
    case 'daily_stats':
      return <DailyStatsContent data={props.data} show={props.show} />
    
    case 'commit_stats':
      return <CommitStatsContent data={props.data} show={props.show} />
    
    case 'build_status':
      return <BuildStatusContent data={props.data} show={props.show} />
    
    case 'stream_goals':
      return <StreamGoalsContent data={props.data} show={props.show} />
    
    default:
      return <DefaultContent type={props.type} data={props.data} show={props.show} />
  }
}

// Content Components - minimal markup with data attributes for styling
function AlertContent(props: { data: any; show?: string }) {
  return (
    <div class="content-alert">
      <div class="alert-message">{props.data?.message || 'Breaking News'}</div>
    </div>
  )
}

function SubTrainContent(props: { data: any; show?: string }) {
  return (
    <div class="content-sub-train">
      <div class="train-count">{props.data?.count || 1}</div>
      <div class="train-subscriber">{props.data?.latest_subscriber || props.data?.subscriber || 'Unknown'}</div>
      <div class="train-tier">{props.data?.latest_tier || props.data?.tier || '1000'}</div>
    </div>
  )
}

function EmoteStatsContent(props: { data: any; show?: string }) {
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

function FollowsContent(props: { data: any; show?: string }) {
  const followers = () => props.data?.recent_followers || []
  
  return (
    <div class="content-follows">
      <div class="follow-list">
        {followers().slice(0, 3).map((follower: string) => (
          <div class="follower">{follower}</div>
        ))}
      </div>
    </div>
  )
}

function IronmonStatsContent(props: { data: any; show?: string }) {
  return (
    <div class="content-ironmon">
      <div class="ironmon-run">Run #{props.data?.run_number || '?'}</div>
      <div class="ironmon-deaths">Deaths: {props.data?.deaths || 0}</div>
      <div class="ironmon-location">{props.data?.location || 'Unknown'}</div>
      <div class="ironmon-gym-progress">Gyms: {props.data?.gym_progress || 0}</div>
    </div>
  )
}

function DailyStatsContent(props: { data: any; show?: string }) {
  return (
    <div class="content-daily-stats">
      <div class="stat-messages">Messages: {props.data?.total_messages || 0}</div>
      <div class="stat-follows">Follows: {props.data?.total_follows || 0}</div>
    </div>
  )
}

function CommitStatsContent(props: { data: any; show?: string }) {
  return (
    <div class="content-commit-stats">
      <div class="commits-today">Commits: {props.data?.commits_today || 0}</div>
      <div class="lines-added">+{props.data?.lines_added || 0}</div>
      <div class="lines-removed">-{props.data?.lines_removed || 0}</div>
    </div>
  )
}

function BuildStatusContent(props: { data: any; show?: string }) {
  return (
    <div class="content-build-status">
      <div class="build-status">{props.data?.status || 'unknown'}</div>
      <div class="build-time">{props.data?.last_build || 'never'}</div>
      <div class="build-coverage">{props.data?.coverage || '0%'}</div>
    </div>
  )
}

function StreamGoalsContent(props: { data: any; show?: string }) {
  const followerGoal = () => props.data?.follower_goal || { current: 0, target: 0 }
  const subGoal = () => props.data?.sub_goal || { current: 0, target: 0 }
  
  return (
    <div class="content-stream-goals">
      <div class="goal-followers">
        <span class="goal-current">{followerGoal().current}</span>
        <span class="goal-separator">/</span>
        <span class="goal-target">{followerGoal().target}</span>
      </div>
      <div class="goal-subs">
        <span class="goal-current">{subGoal().current}</span>
        <span class="goal-separator">/</span>
        <span class="goal-target">{subGoal().target}</span>
      </div>
    </div>
  )
}

function DefaultContent(props: { type: string; data: any; show?: string }) {
  return (
    <div class="content-default">
      <div class="content-type">{props.type.replace(/_/g, ' ')}</div>
      <div class="content-data">{JSON.stringify(props.data, null, 2)}</div>
    </div>
  )
}