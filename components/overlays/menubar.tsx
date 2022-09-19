import React from 'react'
import Clock from 'react-live-clock'

export const MenuBar = () => {
  return (
    <div className="absolute w-[1920px] h-12 px-6 flex items-center backdrop-blur-xl bg-black/25 text-system">
      <div className="flex-auto font-bold text-white">Avalonstar</div>
      <div className="flex-1 text-gray-100 text-right tabular-nums">
        <Clock ticking format="MMM D h:mm A" />
      </div>
    </div>
  )
}
