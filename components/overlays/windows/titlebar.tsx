import { AnimatePresence, LayoutGroup, motion } from 'framer-motion'
import { FC, PropsWithChildren } from 'react'
import Icon from '~/components/icons'

export const TitleBar: FC<PropsWithChildren> = ({ children }) => {
  return (
    <div className="absolute grid grid-cols-[288px_1600px] items-stretch w-full h-[52px] rounded-t-lg text-[#E5E5E5] z-50">
      <div className="flex items-center gap-3 px-5 justify-end">
        <Icon icon="chromecast-line" size={24} className="text-white/50" />
      </div>
      <LayoutGroup>
        <motion.div
          layout
          className="flex items-center justify-center gap-3 px-3 shadow-titlebar-inset bg-titlebar rounded-tr-lg overflow-hidden"
        >
          <Icon icon="chevron-left-line" size={24} className="text-white/50" />
          <Icon icon="chevron-right-line" size={24} className="text-white/50" />
          {children}
          <Icon icon="menu-line" size={24} className="text-white/50" />
        </motion.div>
      </LayoutGroup>
    </div>
  )
}
