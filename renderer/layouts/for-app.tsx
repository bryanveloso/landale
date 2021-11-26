import * as React from 'react'

import { Box } from '@landale/components/box'
import { Grid } from '@landale/components/grid'

const Layout = ({ children }) => (
  <Grid
    css={{
      background: '$slate1',
      position: 'relative',
      gridTemplateColumns: '200px 1fr',
      height: '100%'
    }}
  >
    <Box css={{ background: '$slate2' }}>.</Box>
    <Box>{children}</Box>
  </Grid>
)

export const getLayout: React.FC = page => <Layout>{page}</Layout>
