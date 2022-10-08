import { AnimatePresence } from 'framer-motion'
import dynamic from 'next/dynamic'
import { FC, Suspense } from 'react'

import { useChannel } from '~/hooks'

const GenshinModule = dynamic(() => import('./genshin/sidebar-module'), {
  suspense: true
})

const SidebarModule: FC = () => {
  const { data } = useChannel()

  const getModule = () => {
    switch (data?.game) {
      case 'Genshin Impact':
        return <GenshinModule />

      default:
        return <div />
    }
  }

  return (
    <AnimatePresence>
      <Suspense fallback={'Loading...'}>{getModule()}</Suspense>
    </AnimatePresence>
  )
}

export default SidebarModule
