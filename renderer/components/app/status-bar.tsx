import { Box } from '../box'
import { useOBS } from '../../lib/providers/obs'
import { styled } from '../../stitches.config'

export const StatusBar = () => {
  const { isOBSConnected } = useOBS()

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
      <Status connected={isOBSConnected} /> OBS Studio
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
