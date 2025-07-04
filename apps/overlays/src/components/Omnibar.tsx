import { createSignal, createEffect, Show } from 'solid-js'
import { useStreamChannel, StreamState } from '../hooks/useStreamChannel'

interface OmnibarProps {
  serverUrl?: string
}

export function Omnibar(props: OmnibarProps) {
  const { streamState, isConnected } = useStreamChannel(props.serverUrl)
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
        data-omnibar
        data-show={streamState().current_show}
        data-priority={streamState().priority_level}
        data-connected={isConnected()}
      >
        {renderContent()}
        
        {/* Debug info - you can style or remove this */}
        {import.meta.env.DEV && (
          <div data-omnibar-debug>
            <div>Show: {streamState().current_show}</div>
            <div>Priority: {streamState().priority_level}</div>
            <div>Connected: {isConnected() ? '✓' : '✗'}</div>
            <div>Content: {streamState().active_content?.type || 'none'}</div>
          </div>
        )}
      </div>
    </Show>
  )
}

// Content Components - minimal markup, you style these

function EmoteStatsContent(props: { data: any }) {
  return (
    <div data-content="emote-stats">
      <div data-content-type>Emote Stats</div>
      <div data-emote-list>
        {Object.entries(props.data.emotes || {}).slice(0, 3).map(([emote, count]) => (
          <div data-emote key={emote}>
            <span data-emote-name>{emote}</span>
            <span data-emote-count>{count as number}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function SubTrainContent(props: { data: any }) {
  return (
    <div data-content="sub-train">
      <div data-content-type>Sub Train</div>
      <div data-train-count>{props.data.count || 1}</div>
      <div data-train-latest>{props.data.latest_subscriber}</div>
    </div>
  )
}

function AlertContent(props: { data: any }) {
  return (
    <div data-content="alert">
      <div data-content-type>Alert</div>
      <div data-alert-message>{props.data.message || 'Breaking News'}</div>
    </div>
  )
}

function IronmonStatsContent(props: { data: any }) {
  return (
    <div data-content="ironmon">
      <div data-content-type>IronMON</div>
      <div data-ironmon-run>Run #{props.data.run_number || '?'}</div>
      <div data-ironmon-deaths>Deaths: {props.data.deaths || 0}</div>
      <div data-ironmon-location>{props.data.location || 'Unknown'}</div>
    </div>
  )
}

function FollowsContent(props: { data: any }) {
  return (
    <div data-content="follows">
      <div data-content-type>Recent Follows</div>
      <div data-follow-list>
        {(props.data.recent_followers || []).slice(0, 3).map((follower: string) => (
          <div data-follower key={follower}>{follower}</div>
        ))}
      </div>
    </div>
  )
}

function DefaultContent(props: { type: string; data: any }) {
  return (
    <div data-content="default">
      <div data-content-type>{props.type.replace(/_/g, ' ')}</div>
      <pre data-content-data>{JSON.stringify(props.data, null, 2)}</pre>
    </div>
  )
}