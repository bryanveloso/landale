'use client';

import type { FC, PropsWithChildren, ReactNode } from 'react';

/**
 * OBS Browser Source Dimensions: 1920x1080.
 */

type LayoutProps = PropsWithChildren<{}> & {
  ticker: ReactNode;
};

const Layout: FC<LayoutProps> = props => {
  return (
    <main className="flex h-screen flex-col">
      {props.children}
      {props.ticker}

      {/* "Fake" Sidebar */}
      <div className="absolute -z-10 ml-[1499px] flex">
        <div className="h-screen w-3 bg-black"></div>
        <div className="h-screen w-3  bg-gradient-to-b from-shark-900 to-shark-950"></div>
      </div>
    </main>
  );
};

export default Layout;
