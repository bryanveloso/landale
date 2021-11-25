import * as React from 'react'

import { Screen } from '@landale/components/overlays'

export const Layout: React.FC = ({ children }) => <Screen>{children}</Screen>

export const getLayout: React.FC = page => <Layout>{page}</Layout>
