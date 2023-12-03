import { FC } from 'react';

import { Controls } from './_components/controls';
import { Indicator } from './_components/indicator';

const Display: FC = () => {
  return (
    <div
      className={` h-full w-48 rounded-sm bg-muted-bluegrey shadow-md shadow-black/75`}
    ></div>
  );
};

/**
 * Browser source size should be 560x294.
 */

export default function () {
  return (
    <div className="m-6 flex w-[640px] flex-col rounded-2xl bg-gradient-to-b from-gradient-lighter to-[#1E2229] shadow-xl shadow-black/50">
      <div className="p-3">
        <Indicator />
        <div className="relative aspect-[4/1] rounded-lg bg-[#13141B] p-3 shadow-[inset_0_0_0_1px_#0E0D12]">
          <div className="flex aspect-[4/1]">
            <Controls />
            <Display />
          </div>
        </div>
      </div>
    </div>
  );
}
