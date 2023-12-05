import { Inter, Karla } from 'next/font/google';

import { cn } from '@/lib/utils';

import { Providers } from './providers';

import './globals.css';

const inter = Inter({ subsets: ['latin'], preload: true, display: 'swap' });

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <Providers>
      <html lang="en" className="h-full">
        <body className={cn(inter.className, 'h-full')}>{children}</body>
      </html>
    </Providers>
  );
}
