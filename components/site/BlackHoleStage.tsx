'use client';

import { useEffect, useRef, useState } from 'react';
import dynamic from 'next/dynamic';
import CanvasErrorBoundary from '@/components/blackhole/CanvasErrorBoundary';
import BlackHoleFallback from '@/components/site/BlackHoleFallback';
import { useMotion } from '@/components/site/MotionProvider';
import styles from '@/components/site/BlackHoleStage.module.css';

const BlackHoleCanvas = dynamic(() => import('@/components/blackhole/BlackHoleCanvas'), {
  ssr: false,
  loading: () => null,
});

function supportsWebGL(): boolean {
  try {
    const canvas = document.createElement('canvas');
    return Boolean(canvas.getContext('webgl2') || canvas.getContext('webgl'));
  } catch {
    return false;
  }
}

export default function BlackHoleStage() {
  const { enabled } = useMotion();
  const rootRef = useRef<HTMLDivElement | null>(null);
  const [webgl, setWebgl] = useState(false);
  const [near, setNear] = useState(false);
  const [tabVisible, setTabVisible] = useState(true);
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const [profile, setProfile] = useState({ quality: 1, pointer: true });

  useEffect(() => {
    setWebgl(supportsWebGL());
    const coarse = window.matchMedia('(pointer: coarse)').matches;
    const small = window.innerWidth < 720;
    setProfile({ quality: coarse || small ? 0.45 : 1, pointer: !coarse });
  }, []);

  useEffect(() => {
    const element = rootRef.current;
    if (!element || typeof IntersectionObserver === 'undefined') {
      setNear(true);
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          setNear(entry.isIntersecting);
        }
      },
      { rootMargin: '200px' },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const onVisibility = () => setTabVisible(!document.hidden);
    onVisibility();
    document.addEventListener('visibilitychange', onVisibility);
    return () => document.removeEventListener('visibilitychange', onVisibility);
  }, []);

  const mountCanvas = webgl && enabled && near && !failed;

  return (
    <div className={styles.stage} ref={rootRef} aria-hidden="true">
      <div className={styles.inner}>
        <div className={styles.fallback} data-hidden={ready && mountCanvas ? 'true' : undefined}>
          <BlackHoleFallback />
        </div>
        {mountCanvas ? (
          <div className={styles.canvas} data-visible={ready ? 'true' : undefined}>
            <CanvasErrorBoundary onError={() => setFailed(true)}>
              <BlackHoleCanvas
                intensity={1}
                quality={profile.quality}
                pointerEnabled={profile.pointer}
                paused={!tabVisible}
                onReady={() => setReady(true)}
                onContextLost={() => setFailed(true)}
              />
            </CanvasErrorBoundary>
          </div>
        ) : null}
      </div>
    </div>
  );
}
