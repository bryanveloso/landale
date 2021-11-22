import { Screen } from '../components/screen'
import { TitleBar } from '../components/title-bar'
import { Window } from '../components/window'

const Activity = () => {
  return (
    <Screen>
      <Window size="secondary-434p" css={{ right: 54, top: 323, zIndex: 1 }}>
        <TitleBar style="translucent" controls="active" />
      </Window>
    </Screen>
  )
}

export default Activity
