import type { Metadata } from 'next';
import { Inter, JetBrains_Mono, Space_Grotesk } from 'next/font/google';
import DotField from '@/components/site/DotField';
import Header from '@/components/site/Header';
import Marquee from '@/components/site/Marquee';
import { MotionProvider } from '@/components/site/MotionProvider';
import { siteMeta } from '@/content/site';
import '@/styles/globals.css';

const spaceGrotesk = Space_Grotesk({
  subsets: ['latin'],
  weight: ['400', '500', '600'],
  variable: '--font-space',
  display: 'swap',
});

const inter = Inter({
  subsets: ['latin'],
  weight: ['400', '500', '600'],
  variable: '--font-inter',
  display: 'swap',
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  weight: ['400', '500'],
  variable: '--font-jetbrains',
  display: 'swap',
});

export const metadata: Metadata = {
  title: siteMeta.title,
  description: siteMeta.description,
  icons: { icon: '/favicon.ico' },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="pt-BR"
      className={`${spaceGrotesk.variable} ${inter.variable} ${jetbrainsMono.variable}`}
    >
      <body>
        <MotionProvider>
          <a className="skipLink" href="#main">
            Pular para o conteúdo
          </a>
          <DotField />
          <Marquee />
          <Header />
          <main id="main">{children}</main>
        </MotionProvider>
      </body>
    </html>
  );
}
