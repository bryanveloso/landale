import * as React from 'react'

import { Box } from '@landale/components/box'
import { Grid } from '@landale/components/grid'

const Layout = ({ children }) => (
  <Grid
    css={{
      background: '$backgroundSecondary',
      position: 'relative',
      gridTemplateColumns: '200px 1fr',
      height: '100%'
    }}
  >
    <Box css={{ background: '$backgroundPrimary' }}>
      <Box css={{ height: 38, '-webkit-app-region': 'drag' }} />
    </Box>
    <Box>{children}</Box>
  </Grid>
)

export const getLayout: React.FC = page => <Layout>{page}</Layout>
