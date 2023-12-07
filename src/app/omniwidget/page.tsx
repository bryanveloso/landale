import { FC, Suspense } from 'react';

import { Display } from './_components/display';
import { Indicator } from './_components/indicator';

const Page: FC = () => {
  return (
    <div className="h-36 p-3">
      <Indicator />
      <Suspense fallback={null}>
        <Display />
      </Suspense>
    </div>
  );
};

export default Page;
