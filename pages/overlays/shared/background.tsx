import { MenuBar } from 'components/overlays/menubar'
import { Wallpaper } from 'components/overlays/wallpaper'
import { Window } from 'components/overlays/window'

const Background = () => {
  return (
    <>
      <MenuBar />
      <Window />
      <Wallpaper />
    </>
  )
}

export default Background
