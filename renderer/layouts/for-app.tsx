import * as React from 'react'

export const Layout: React.FC = ({ children }) => <>{children}</>

export const getLayout: React.FC = page => <Layout>{page}</Layout>
