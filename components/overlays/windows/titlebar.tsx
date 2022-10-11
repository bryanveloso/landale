import { AnimatePresence, motion } from 'framer-motion'
import { FC, PropsWithChildren } from 'react'

export const TitleBar: FC<PropsWithChildren> = ({ children }) => {
  return (
    <AnimatePresence mode="wait">
      <div className="absolute grid grid-cols-[288px_1600px] items-stretch w-full h-[52px] rounded-t-lg text-[#E5E5E5] z-50">
        <div className="flex items-center gap-3 px-5 justify-end"></div>
        <div className="flex items-center justify-center gap-3 px-5 shadow-titlebar-inset bg-titlebar rounded-tr-lg">
          {children}
        </div>
      </div>
    </AnimatePresence>
  )
}
