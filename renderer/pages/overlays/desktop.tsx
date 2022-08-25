import Image from 'next/image'

import { styled } from '@landale/stitches.config'

import avalonSTAR from '../../public/avalonstar.png'

const Desktop = () => {
  return (
    <MenuBar>
      <Image layout="fixed" src={avalonSTAR} width={16} height={16} priority />
      <strong>Avalonstar</strong>
      <span>Twitch</span>
      <span style={{ color: 'rgba(255, 255, 255, 0.25)' }}>Altair</span>
    </MenuBar>
  )
}

export default Desktop

const MenuBar = styled('div', {
  // display: 'flex',
  display: 'none',
  alignItems: 'center',
  gap: 20,
  height: 37,
  padding: '0 20px',

  backgroundColor: 'rgba(255,255,255,0.05)',
  color: 'white',
  fontSize: 14
})
