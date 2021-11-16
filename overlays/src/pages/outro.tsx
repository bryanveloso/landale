import Image from 'next/image'

import { Screen } from '../components/screen'
import { styled } from '../stitches.config'

import outroHero from '../../public/outro-hero.png'

export default function Outro() {
  return (
    <Screen padded css={{ backgroundColor: 'black', color: 'white' }}>
      <Logo>
        <Image layout="fixed" src={outroHero} width={817} height={156} />
      </Logo>
      <Copyright>&copy; MMXXI</Copyright>
    </Screen>
  )
}

const Logo = styled('div', {
  gridColumn: '1 / -1',
  gridRow: '9',
  textAlign: 'center'
})

const Copyright = styled('div', {
  gridColumn: '1 / -1',
  gridRowEnd: '-1',

  color: '#FFF8CC',
  fontWeight: 800,
  textAlign: 'center'
})
