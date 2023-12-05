import { FC } from 'react';

import { Timecode } from './timecode';

export const Display: FC = () => {
  return (
    <div className="bg-shark-600 flex h-full w-48 flex-col gap-y-2 rounded-md p-3 shadow-[inset_0_1px_0_theme(colors.shark.400)]">
      <div className="bg-ring-black/60 rounded-md"></div>
      <Timecode />
      <div className="h-6 rounded-md bg-black/60"></div>
    </div>
  );
};
