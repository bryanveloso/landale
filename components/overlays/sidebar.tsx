import { FC } from 'react'

import { Logomark } from '~/components/icons'

export const Sidebar: FC = () => {
  return (
    <div className={`h-full w-72 z-40 rounded-l-lg shadow-sidebar-inset`}>
      <div className="flex flex-col h-full">
        <div className="h-[52px]"></div>
        <div className="grow">
          <div className="p-4 text-white">
            <strong className=" text-sm">Avalonstar</strong>
            <div>Talk</div>
            <div>Game</div>
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
