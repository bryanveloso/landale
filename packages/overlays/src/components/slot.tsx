import { FC } from 'react';

export const Slot: FC<{ width: string; height: string }> = ({
  width,
  height,
}) => (
  <div className="from-shark-800 to-shark-900 flex rounded-2xl bg-gradient-to-b shadow-xl shadow-black/50">
    <div className="bg-shark-950 relative m-3 flex rounded-lg p-3 shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
      <div className={`bg-avayellow ${width} ${height}`}></div>
    </div>
  </div>
);
