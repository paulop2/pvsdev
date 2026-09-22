'use client';

import { useState } from 'react';
import { marqueeItems } from '@/content/site';
import { useMotion } from '@/components/site/MotionProvider';
import styles from '@/components/site/Marquee.module.css';

function Group({ hidden }: { hidden?: boolean }) {
  return (
    <ul className={styles.group} aria-hidden={hidden ? true : undefined}>
      {marqueeItems.map((item) => (
        <li key={item} className={styles.item}>
          <span className={styles.sep} aria-hidden="true">
            +
          </span>
          {item}
        </li>
      ))}
    </ul>
  );
}

export default function Marquee() {
  const { enabled } = useMotion();
  const [paused, setPaused] = useState(false);
  const isPaused = paused || !enabled;

  return (
    <div className={styles.marquee}>
      <div className={styles.viewport}>
        <div className={styles.track} data-paused={isPaused ? 'true' : undefined}>
          <Group />
          <Group hidden />
        </div>
      </div>
      <button
        type="button"
        className={styles.pause}
        aria-pressed={isPaused}
        aria-label={isPaused ? 'Retomar faixa de texto' : 'Pausar faixa de texto'}
        onClick={() => setPaused((value) => !value)}
      >
        <span aria-hidden="true">{isPaused ? '▶' : '❙❙'}</span>
      </button>
    </div>
  );
}
