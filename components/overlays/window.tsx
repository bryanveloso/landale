import { FC } from 'react'

export const Controls = () => {
  return (
    <div className="absolute flex h-[52px] items-center gap-2 px-5 z-50">
      <div className="w-3 h-3 rounded-full bg-[#FF453A]" />
      <div className="w-3 h-3 rounded-full bg-[#FFD60A]" />
      <div className="w-3 h-3 rounded-full bg-[#32D74B]" />
    </div>
  )
}

const TitleBar = () => {
  return (
    <div className="absolute flex w-full h-[52px] bg-titlebar rounded-t-lg"></div>
  )
}

const Sidebar = () => {
  return <div className="bg-sidebar h-full w-72 z-40 rounded-l-lg"></div>
}

export interface WindowProps {
  height: string
  width: string
}

export const Window: FC<WindowProps> = ({ height, width }) => {
  return (
    <div
      className={`absolute m-4 mt-16 w-[${width}] h-[${height}] rounded-lg shadow-2xl bg-window shadow-black/50 backdrop-blur-xl ring-1 ring-black ring-offset-0`}
    >
      <div className="absolute w-full h-full rounded-lg ring-2 ring-offset-0 ring-inset ring-white/10 z-50"></div>
      <Controls />
      <div className="grid grid-cols-[288px_1600px] h-full">
        <Sidebar />
      </div>
      {/* <TitleBar /> */}
    </div>
  )
}
