import { Show, type JSX } from 'solid-js'

export type OmnibarRootProps = {
  show: () => boolean
  rootProps?: JSX.HTMLAttributes<HTMLDivElement>
  children: JSX.Element
}

export function OmnibarRoot(props: OmnibarRootProps) {
  return (
    <Show when={props.show()}>
      <div {...props.rootProps}>{props.children}</div>
    </Show>
  )
}
