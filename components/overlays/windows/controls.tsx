import { FC } from 'react'

export const Controls: FC = () => {
  return (
    <div className="absolute flex h-[52px] items-center gap-2 px-5 z-50">
      <div className="w-3 h-3 rounded-full bg-[#FF453A]" />
      <div className="w-3 h-3 rounded-full bg-[#FFD60A]" />
      <div className="w-3 h-3 rounded-full bg-[#32D74B]" />
    </div>
  )
}
