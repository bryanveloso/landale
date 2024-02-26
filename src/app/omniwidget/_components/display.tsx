import { FC } from 'react';

import { Timecode } from './timecode';
import { Muted, Unmuted, Video } from '@/app/ui/icons';

export const Display: FC = () => {
  let now = new Date();

  return (
    <div className="flex h-full flex-col gap-y-2">
      <div className="flex w-48 flex-auto flex-col gap-y-1.5 rounded-md bg-shark-600 p-3 shadow-[inset_0_1px_0_theme(colors.shark.400)]">
        <div className="flex justify-between">
          <div className="flex rounded-sm p-1 ring-1 ring-shark-800">
            <Video className="h-3 w-3 text-shark-800" />
          </div>
          <div className="rounded-sm p-1 ring-1 ring-shark-800">
            <Unmuted className="h-3 w-3 text-shark-800" />
          </div>
        </div>
        <Timecode />
      </div>
      <div className="text-sm text-shark-100">
        <span>AVLN {now.toISOString().slice(0, 10)}.mkv</span>
      </div>
    </div>
  );
};
