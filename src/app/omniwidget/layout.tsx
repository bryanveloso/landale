import Image from 'next/image';
import { FC, PropsWithChildren, ReactNode } from 'react';

/**
 * OBS Browser Source Dimensions: 1920x284.
 */

type LayoutProps = PropsWithChildren<{}> & {
  rainwave: ReactNode;
  twitch: ReactNode;
};

const Layout: FC<LayoutProps> = props => {
  return (
    <main className="flex items-end justify-end">
      <div className="bg-shark-950/30  m-6 flex flex-col  rounded-2xl">
        <div className="flex justify-end rounded-l-2xl p-6 py-4">
          <Image
            src="/avalonstar.png"
            width={36}
            height={36}
            alt="Avocadostar"
            priority
          />
        </div>
        <div>
          {/* <div className="ring-1 ring-purple-500">{props.twitch}</div> */}
          <div className="from-shark-800 to-shark-900 flex rounded-2xl bg-gradient-to-b shadow-xl shadow-black/50">
            <div className="bg-shark-950 relative m-3 flex rounded-lg shadow-[inset_0_0_0_1px_theme(colors.shark.950)]">
              <div className="h-36">{props.rainwave}</div>
              <div className="h-36">{props.children}</div>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
};

export default Layout;
