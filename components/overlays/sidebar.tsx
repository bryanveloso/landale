import dynamic from 'next/dynamic'

import { FC, Suspense } from 'react'

import { Logomark } from '~/components/icons'

const GenshinModule = dynamic(() => import('../games/genshin/module'), {
  suspense: true
})

const navigationItems = [
  {
    label: 'Talk'
  },
  {
    label: 'Game'
  }
]

const Navigation: FC = () => {
  return (
    <div className="p-4 text-sm text-white">
      <div>
        <strong className="">Scenes</strong>
      </div>
      {navigationItems.map(item => {
        return (
          <div className="flex py-3 gap-2">
            <div>icon</div>
            <div>{item.label}</div>
          </div>
        )
      })}
    </div>
  )
}

export const Sidebar: FC = () => {
  return (
    <div className={`h-full w-72 z-40 rounded-l-lg shadow-sidebar-inset`}>
      <div className="flex flex-col h-full">
        <div className="h-[52px]"></div>
        <div className="grow">
          <div className="">
            <Navigation />
            <Suspense fallback={'Loading...'}>
              <GenshinModule />
            </Suspense>
          </div>
        </div>
        <div className="text-white">
          <div className="p-8">
            <Logomark className="h-12 mx-auto opacity-10" />
          </div>
        </div>
      </div>
    </div>
  )
}
