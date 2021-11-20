import Image from 'next/image'
import { m } from 'framer-motion'

import { Screen } from '../components/screen'
import { styled } from '../stitches.config'

import outroHero from '../../public/outro-hero.png'

export default function Outro() {
  return (
    <Screen padded>
      <Logo>
        <Image layout="fixed" src={outroHero} width={817} height={156} />
      </Logo>
      <Copyright
        initial={{ opacity: 0 }}
        animate={{ opacity: 1, transition: { delay: 1 } }}
      >
        &copy; MMXXI
      </Copyright>
    </Screen>
  )
}

const Logo = styled('div', {
  gridColumn: '1 / -1',
  gridRow: '9',
  textAlign: 'center'
})

const Copyright = styled(m.div, {
  gridColumn: '1 / -1',
  gridRow: '19',

  color: '#FFF8CC',
  fontWeight: 800,
  textAlign: 'center'
})
