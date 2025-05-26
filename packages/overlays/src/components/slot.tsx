import { FC, PropsWithChildren } from 'react'

type Slot = PropsWithChildren<{
  width: string
  height?: string
}>

export const Slot: FC<Slot> = ({ children, width, height }) => (
  <div className="bg-shark-900 flex rounded-2xl bg-gradient-to-b from-white/20 to-black/20 bg-blend-soft-light shadow-xl ring-2 shadow-black/50 ring-white/10 ring-inset">
    <div className="bg-shark-950 shadow-[inset_0_0_0_1px_theme(colors.shark.950)] relative m-3 flex rounded-lg p-1.5">
      <div className={`${width} ${height}`}>{children}</div>
    </div>
  </div>
)
