import { FC } from 'react'

const Controls = () => {
  return (
    <div className="flex items-center gap-2 px-5">
      <div className="w-3 h-3 rounded-full bg-red-600"></div>
      <div className="w-3 h-3 rounded-full bg-yellow-600 "></div>
      <div className="w-3 h-3 rounded-full bg-green-600"></div>
    </div>
  )
}

const TitleBar = () => {
  return (
    <div className="absolute flex w-full h-[52px] rounded-t-lg">
      <Controls />
    </div>
  )
}

export interface WindowProps {
  height: string
  width: string
}

export const Window: FC<WindowProps> = ({ height, width }) => {
  return (
    <div
      className={`absolute m-4 mt-16 w-[${width}] h-[${height}] bg-black/5 rounded-lg shadow-2xl shadow-black/50 backdrop-blur-xl ring-1 ring-black ring-offset-0`}
    >
      <TitleBar />
      <div className="w-full h-full rounded-lg ring-2 ring-offset-0 ring-inset ring-white/10 z-10"></div>
    </div>
  )
}
