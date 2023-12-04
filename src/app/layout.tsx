import { Inter, Karla } from 'next/font/google';

import { Providers } from './providers';

import './globals.css';
import { cn } from '@/lib/utils';

const inter = Inter({ subsets: ['latin'], preload: true, display: 'swap' });

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <Providers>
      <html lang="en">
        <body className={cn(inter.className)}>{children}</body>
      </html>
    </Providers>
  );
}
