import Image from 'next/image';
import { FC, PropsWithChildren, ReactNode } from 'react';

/**
 * OBS Browser Source Dimensions: 1920x216.
 */

type LayoutProps = PropsWithChildren<{}> & {
  rainwave: ReactNode;
  twitch: ReactNode;
};

const Layout: FC<LayoutProps> = props => {
  return (
    <main className="flex items-end justify-end">
      <div className="m-6 flex items-start">
        <div className="m-6">
          <Image
            src="/avalonstar.png"
            width={36}
            height={36}
            alt="Avocadostar"
            priority
          />
        </div>
        {/* <div className="ring-1 ring-purple-500">{props.twitch}</div> */}
        <div className="flex rounded-2xl bg-gradient-to-b from-gradient-lighter to-[#1E2229] shadow-xl shadow-black/50">
          <div className="relative m-3 flex rounded-lg bg-[#13141B] shadow-[inset_0_0_0_1px_#0E0D12]">
            <div className="h-36">{props.rainwave}</div>
            <div className="h-36">{props.children}</div>
          </div>
        </div>
      </div>
    </main>
  );
};

export default Layout;
