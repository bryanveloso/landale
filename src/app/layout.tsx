import { Inter } from 'next/font/google';

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
      <html lang="en">
        <body className={inter.className}>{children}</body>
      </html>
    </Providers>
  );
}
