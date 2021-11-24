import { motion } from 'framer-motion'
import Image from 'next/image'

import { Box } from '../components/box'
import { styled } from '../stitches.config'

import avalonSTAR from '../../public/avalonstar.png'

export default function Intro() {
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
          src={avalonSTAR}
          width={112}
          height={112}
          priority
        />
      </Logo>

      <div className="busy-loader">
        <div className="w-ball-wrapper ball-1">
          <div className="w-ball"></div>
        </div>
        <div className="w-ball-wrapper ball-2">
          <div className="w-ball"></div>
        </div>
        <div className="w-ball-wrapper ball-3">
          <div className="w-ball"></div>
        </div>
        <div className="w-ball-wrapper ball-4">
          <div className="w-ball"></div>
        </div>
        <div className="w-ball-wrapper ball-5">
          <div className="w-ball"></div>
        </div>
      </div>
    </Box>
  )
}

const Logo = styled('div', {
  display: 'flex',
  height: '75%',
  justifyContent: 'center',
  alignItems: 'center'
})

const Copyright = styled(motion.div, {
  color: '#FFF8CC',
  fontWeight: 800,
  textAlign: 'center',
  textTransform: 'uppercase'
})
