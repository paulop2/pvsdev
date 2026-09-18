'use client';

import dynamic from 'next/dynamic';

const BoxesCanvas = dynamic(() => import('@/components/BoxesCanvas'), {
  ssr: false,
  loading: () => <p>Carregando…</p>,
});

export default function BoxesScene() {
  return <BoxesCanvas />;
}
