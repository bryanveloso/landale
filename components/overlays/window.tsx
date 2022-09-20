import { FC, HTMLAttributes } from 'react'

export const Controls: FC = () => {
  return (
    <div className="absolute flex h-[52px] items-center gap-2 px-5 z-50">
      <div className="w-3 h-3 rounded-full bg-[#FF453A]" />
      <div className="w-3 h-3 rounded-full bg-[#FFD60A]" />
      <div className="w-3 h-3 rounded-full bg-[#32D74B]" />
    </div>
  )
}

const VideoGamePC: FC<HTMLAttributes<'svg'>> = ({ className }) => {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      className={className}
    >
      <g>
        <path
          d="M6,3.75H9a2,2,0,0,1,2,2v4.5a1,1,0,0,0,2,0V5.75a4,4,0,0,0-4-4H6a1,1,0,0,0,0,2Z"
          fill="currentColor"
        />
        <path
          d="M18.5,11.25a5.54,5.54,0,0,0-3.64,1.37.46.46,0,0,1-.33.13H9.47a.46.46,0,0,1-.33-.13,5.5,5.5,0,1,0,0,8.26.46.46,0,0,1,.33-.13h5.06a.46.46,0,0,1,.33.13,5.5,5.5,0,1,0,3.64-9.63Zm-11.25,6H6.5a.5.5,0,0,0-.5.5v.75a.75.75,0,0,1-1.5,0v-.75a.5.5,0,0,0-.5-.5H3.25a.75.75,0,0,1,0-1.5H4a.5.5,0,0,0,.5-.5V14.5a.75.75,0,0,1,1.5,0v.75a.5.5,0,0,0,.5.5h.75a.75.75,0,0,1,0,1.5Zm8.75.5a1,1,0,1,1,1-1A1,1,0,0,1,16,17.75Zm2.5,2.5a1,1,0,1,1,1-1A1,1,0,0,1,18.5,20.25Zm0-5a1,1,0,1,1,1-1A1,1,0,0,1,18.5,15.25Zm2.5,2.5a1,1,0,1,1,1-1A1,1,0,0,1,21,17.75Z"
          fill="currentColor"
        />
      </g>
    </svg>
  )
}

const NavigationMenu: FC<HTMLAttributes<'svg'>> = ({ className }) => {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      className={className}
    >
      <g>
        <rect
          x={0.5}
          y={2.5}
          width={23}
          height={3}
          rx={1}
          fill="currentColor"
        />
        <rect
          x={0.5}
          y={10.5}
          width={23}
          height={3}
          rx={1}
          fill="currentColor"
        />
        <rect
          x={0.5}
          y={18.5}
          width={23}
          height={3}
          rx={1}
          fill="currentColor"
        />
      </g>
    </svg>
  )
}

const TitleBar = () => {
  return (
    <div className="absolute grid grid-cols-[288px_1600px] items-stretch w-full h-[52px] rounded-t-lg text-[#E5E5E5] z-50">
      <div></div>
      <div className="flex items-center gap-3 px-5 shadow-titlebar-inset bg-titlebar rounded-tr-lg">
        <VideoGamePC className="w-6 h-6" />
        <div className="font-medium">Destiny 2</div>
        {/* <NavigationMenu className="w-6 h-6" /> */}
      </div>
    </div>
  )
}

const Sidebar: FC = () => {
  return (
    <div className="bg-sidebar h-full w-72 z-40 rounded-l-lg shadow-sidebar-inset"></div>
  )
}

export interface WindowProps {
  category?: string
}

export const Window: FC<WindowProps> = ({ category }) => {
  return (
    <div
      className={`absolute m-4 mt-16 w-[1888px] h-[952px] rounded-lg shadow-2xl bg-window shadow-black/50 backdrop-blur-xl ring-1 ring-black ring-offset-0`}
    >
      <div className="absolute w-full h-full rounded-lg ring-2 ring-offset-0 ring-inset ring-white/10 z-50"></div>
      <Controls />
      <TitleBar />
      <div className="grid grid-cols-[288px_1600px] h-full">
        <Sidebar />
      </div>
      {/* <TitleBar /> */}
    </div>
  )
}
