import { MenuBar } from 'components/overlays/menubar'
import { Wallpaper } from 'components/overlays/wallpaper'
import { Window } from 'components/overlays/window'

const Shared = () => {
  return (
    <>
      <MenuBar />
      <Window height="952px" width="1888px" />
      <Wallpaper />
    </>
  )
}

export default Shared
