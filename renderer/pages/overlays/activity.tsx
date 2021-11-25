import { Screen } from '@landale/components/screen'
import { TitleBar } from '@landale/components/title-bar'
import { Window } from '@landale/components/window'
import { getLayout } from '@landale/layouts/for-overlay'

const Activity = () => {
  return (
    <Window size="secondary-434p" css={{ right: 54, top: 323, zIndex: 1 }}>
      <TitleBar style="translucent" controls="active" />
    </Window>
  )
}

export default Activity

Activity.getLayout = getLayout
