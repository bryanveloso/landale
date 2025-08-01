export type OmnibarDebugProps = {
  activeContent: string
  stackSize: number
  layerStates: {
    foreground: string
    midground: string
    background: string
  }
}

export function OmnibarDebug(props: OmnibarDebugProps) {
  return (
    <div class="omnibar-debug">
      <div>Foreground: {props.layerStates.foreground}</div>
      <div>Midground: {props.layerStates.midground}</div>
      <div>Background: {props.layerStates.background}</div>
      <div>Active: {props.activeContent}</div>
      <div>Stack: {props.stackSize}</div>
    </div>
  )
}
