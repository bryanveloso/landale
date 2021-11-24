import { motion } from 'framer-motion'
import Image from 'next/image'

import { Box } from '../components/box'
import { styled } from '../stitches.config'

import outroHero from '../../public/outro-hero.png'

export default function Outro() {
  return (
    <Box
      css={{
        display: 'flex',
        flexDirection: 'column',
        height: 'calc(100% - 108px)',
        padding: 54
      }}
    >
      <Logo>
        <Image
          layout="fixed"
          src={outroHero}
          width={184}
          height={156}
          priority
        />
      </Logo>
      <Copyright
        initial={{ opacity: 0 }}
        animate={{ opacity: 1, transition: { delay: 1 } }}
      >
        &copy; Avalonstar Incorporated MMXXI. All Rights Reserved.
      </Copyright>
    </Box>
  )
}

const Logo = styled('div', {
  display: 'flex',
  height: '100%',
  justifyContent: 'center',
  alignItems: 'center'
})

const Copyright = styled(motion.div, {
  color: '#FFF8CC',
  fontWeight: 800,
  textAlign: 'center',
  textTransform: 'uppercase'
})
