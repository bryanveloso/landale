import cn from 'classnames'
import { FC, PropsWithChildren } from 'react'

import { Logomark, VideoGamePC } from '~/components/icons'

export const Controls: FC = () => {
  return (
    <div className="absolute flex h-[52px] items-center gap-2 px-5 z-50">
      <div className="w-3 h-3 rounded-full bg-[#FF453A]" />
      <div className="w-3 h-3 rounded-full bg-[#FFD60A]" />
      <div className="w-3 h-3 rounded-full bg-[#32D74B]" />
    </div>
  )
}

export interface TitleBarProps {
  category?: string
}

export const TitleBar: FC<TitleBarProps> = ({ category }) => {
  return (
    <div className="absolute grid grid-cols-[288px_1600px] items-stretch w-full h-[52px] rounded-t-lg text-[#E5E5E5] z-50">
      <div className="flex items-center gap-3 px-5 justify-end"></div>
      <div className="flex items-center gap-3 px-5 shadow-titlebar-inset bg-titlebar rounded-tr-lg">
        <VideoGamePC className="w-6 h-6" />
        <div className="font-semibold">{category}</div>
      </div>
    </div>
  )
}

export const Sidebar: FC = () => {
  return (
    <div className={`h-full w-72 z-40 rounded-l-lg shadow-sidebar-inset`}>
      <div className="flex flex-col h-full">
        <div className="h-[52px]"></div>
        <div className="grow"></div>
        <div className="text-white">
          <div className="p-8">
            <Logomark className="h-12 mx-auto opacity-10" />
          </div>
        </div>
      </div>
    </div>
  )
}

export const Window: FC<PropsWithChildren> = ({ children }) => {
  return (
    <div
      className={`absolute m-4 mt-16 w-[1888px] h-[952px] rounded-lg shadow-2xl bg-window backdrop-blur-xl shadow-black/50 ring-1 ring-black ring-offset-0 z-20`}
    >
      {children}
    </div>
  )
}
