import { GeistSans } from 'geist/font/sans';
import { GeistMono } from 'geist/font/mono';
import { Inter, Karla } from 'next/font/google';

import { cn } from '@/lib/utils';

import { Providers } from './providers';

import './globals.css';

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <Providers>
      <html
        lang="en"
        className={`h-full ${GeistSans.variable} ${GeistMono.variable}`}
      >
        <body className="h-full">{children}</body>
      </html>
    </Providers>
  );
}
