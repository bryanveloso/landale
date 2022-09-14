import { useObs } from '@landale/hooks'

import { Box } from '../box'
import { styled } from '../../stitches.config'

export const StatusBar = () => {
  const { connected } = useObs()

  return (
    <Box
      css={{
        alignItems: 'center',
        display: 'flex',
        padding: '10px 0px 10px',
        width: '100%',

        fontSize: 12,
        fontWeight: 'bold'
      }}
    >
      <Status connected={connected} /> OBS Studio
    </Box>
  )
}

const Status = styled('div', {
  backgroundColor: '$red11',
  width: 8,
  height: 8,
  marginRight: 6,
  borderRadius: '50%',

  variants: {
    connected: {
      true: {
        backgroundColor: '$green11'
      }
    }
  }
})
