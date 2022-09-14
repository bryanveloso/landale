import * as React from 'react'

import { Box } from '@landale/components/box'
import { Grid } from '@landale/components/grid'
import { StatusBar } from '@landale/components/app/status-bar'

const Layout = ({ children }) => (
  <Grid
    css={{
      background: '$backgroundPrimary',
      position: 'relative',
      gridTemplateColumns: '200px 1fr',
      gridTemplateRows: '38px 1fr',
      height: '100%'
    }}
  >
    <Box css={{ gridColumn: 1, gridRow: 1, '-webkit-app-region': 'drag' }} />
    <Box css={{ gridColumn: 2, gridRow: 1, '-webkit-app-region': 'drag' }}>
      <StatusBar />
    </Box>
    <Box>
      <Box css={{ height: 38, '-webkit-app-region': 'drag' }} />
    </Box>
    <Box>{children}</Box>
  </Grid>
)

export const getLayout: React.FC = page => <Layout>{page}</Layout>
