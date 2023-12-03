import Image from 'next/image';

import { Rainwave } from '@/components/modules/rainwave';
import { Logomark } from './logomark';

export const Controls = () => {
  return (
    <div className="flex flex-auto flex-col p-2">
      <div className="flex-auto">
        <Logomark />
      </div>
      <Rainwave />
    </div>
  );
};
