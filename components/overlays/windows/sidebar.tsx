import { FC, PropsWithChildren } from 'react'
import SidebarModule from '~/components/games/sidebar-module'

import { Logomark } from '~/components/icons'

export const Sidebar: FC = () => {
  return (
    <div className={`h-full w-full z-40 rounded-l-lg shadow-sidebar-inset`}>
      <div className="flex flex-col h-full">
        <div className="h-[52px]"></div>
        <div className="grow">
          <SidebarModule />
        </div>
      </div>
    </div>
  )
}
