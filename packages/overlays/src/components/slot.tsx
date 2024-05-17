import { FC, PropsWithChildren } from 'react';

type Slot = PropsWithChildren<{
  width: string;
  height: string;
}>;

export const Slot: FC<Slot> = ({ children, width, height }) => (
  <div className="flex rounded-2xl bg-shark-900 bg-gradient-to-b from-white/20 to-black/20 bg-blend-soft-light shadow-xl shadow-black/50 ring-2 ring-inset ring-white/10">
    <div className="relative m-3 flex rounded-lg bg-shark-950 p-1.5 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
      <div className={`bg-avayellow ${width} ${height}`}>{children}</div>
    </div>
  </div>
);
