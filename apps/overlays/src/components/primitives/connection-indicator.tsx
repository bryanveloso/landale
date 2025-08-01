export type ConnectionIndicatorProps = {
  connected: () => boolean
}

export function ConnectionIndicator(props: ConnectionIndicatorProps) {
  return <div class="connection-status" data-connected={props.connected()} />
}
