import { createSignal, createEffect, Show } from 'solid-js'
import { useStreamChannel } from '@/hooks/use-stream-channel'

export function Omnibar() {
  const { streamState, isConnected } = useStreamChannel()
  const [isVisible, setIsVisible] = createSignal(true)

  // Show/hide based on active content
  createEffect(() => {
    const state = streamState()
    const hasContent = state.active_content !== null
    setIsVisible(hasContent)
  })

  const renderContent = () => {
    const content = streamState().active_content
    if (!content) return null

    switch (content.type) {
      case 'emote_stats':
        return <EmoteStatsContent data={content.data} />
      case 'sub_train':
        return <SubTrainContent data={content.data} />
      case 'alert':
        return <AlertContent data={content.data} />
      case 'ironmon_run_stats':
        return <IronmonStatsContent data={content.data} />
      case 'recent_follows':
        return <FollowsContent data={content.data} />
      default:
        return <DefaultContent type={content.type} data={content.data} />
    }
  }

  return (
    <Show when={isVisible()}>
      <div
        class="w-canvas"
        class="omnibar"
        data-show={streamState().current_show}
        data-priority={streamState().priority_level}
        data-connected={isConnected()}>
        {renderContent()}

        {/* Debug info - you can style or remove this */}
        {import.meta.env.DEV && (
          <div class="omnibar-debug">
            <div>Show: {streamState().current_show}</div>
            <div>Priority: {streamState().priority_level}</div>
            <div>Content: {streamState().active_content?.type || 'none'}</div>
          </div>
        )}

        <div classList={{ 'bg-buttermilk': !isConnected(), 'bg-lime': isConnected() }} class="h-0.5"></div>
      </div>
    </Show>
  )
}

// Content Components - minimal markup, you style these

function EmoteStatsContent(props: { data: any }) {
  return (
    <div class="content-emote-stats">
      <div class="content-type">Emote Stats</div>
      <div class="emote-list">
        {Object.entries(props.data.emotes || {})
          .slice(0, 3)
          .map(([emote, count]) => (
            <div class="emote">
              <span class="emote-name">{emote}</span>
              <span class="emote-count">{count as number}</span>
            </div>
          ))}
      </div>
    </div>
  )
}

function SubTrainContent(props: { data: any }) {
  return (
    <div class="content-sub-train">
      <div class="content-type">Sub Train</div>
      <div class="train-count">{props.data.count || 1}</div>
      <div class="train-latest">{props.data.latest_subscriber || props.data.subscriber}</div>
    </div>
  )
}

function AlertContent(props: { data: any }) {
  return (
    <div class="content-alert">
      <div class="content-type">Alert</div>
      <div class="alert-message">{props.data.message || 'Breaking News'}</div>
    </div>
  )
}

function IronmonStatsContent(props: { data: any }) {
  return (
    <div class="content-ironmon">
      <div class="content-type">IronMON</div>
      <div class="ironmon-run">Run #{props.data.run_number || '?'}</div>
      <div class="ironmon-deaths">Deaths: {props.data.deaths || 0}</div>
      <div class="ironmon-location">{props.data.location || 'Unknown'}</div>
    </div>
  )
}

function FollowsContent(props: { data: any }) {
  return (
    <div class="content-follows">
      <div class="content-type">Recent Follows</div>
      <div class="follow-list">
        {(props.data.recent_followers || []).slice(0, 3).map((follower: string) => (
          <div class="follower">{follower}</div>
        ))}
      </div>
    </div>
  )
}

function DefaultContent(props: { type: string; data: any }) {
  return (
    <div class="content-default">
      <div class="content-type">{props.type.replace(/_/g, ' ')}</div>
      <pre class="content-data">{JSON.stringify(props.data, null, 2)}</pre>
    </div>
  )
}
