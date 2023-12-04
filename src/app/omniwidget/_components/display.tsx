'use client';

import { FC } from 'react';

import { Timecode } from './timecode';

export const Display: FC = () => {
  return (
    <div
      className={`flex h-full w-48 flex-col gap-y-2 rounded-md bg-muted-bluegrey p-3 shadow-md shadow-black/75`}
    >
      <div className="mb-2 flex flex-auto justify-between"></div>
      <Timecode />
      <div className="h-6 rounded-md bg-black/60"></div>
    </div>
  );
};
