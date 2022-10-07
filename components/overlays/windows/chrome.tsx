import { FC, PropsWithChildren } from 'react'

export const Window: FC<PropsWithChildren> = ({ children }) => {
  return (
    <div
      className={`absolute m-4 mt-16 w-[1888px] h-[952px] rounded-lg shadow-2xl bg-window backdrop-blur-xl shadow-black/50 ring-1 ring-black ring-offset-0 z-20`}
    >
      {children}
    </div>
  )
}
