'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

interface MotionContextValue {
  enabled: boolean;
  setEnabled: (value: boolean) => void;
  toggle: () => void;
}

const MotionContext = createContext<MotionContextValue | null>(null);

export function MotionProvider({ children }: { children: React.ReactNode }) {
  const [enabled, setEnabled] = useState(true);

  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    setEnabled(!query.matches);
    const onChange = () => setEnabled(!query.matches);
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, []);

  useEffect(() => {
    document.documentElement.dataset.motion = enabled ? 'on' : 'off';
  }, [enabled]);

  useEffect(() => {
    const root = document.documentElement;
    if (typeof IntersectionObserver === 'undefined') {
      return;
    }
    const elements = Array.from(document.querySelectorAll<HTMLElement>('[data-reveal]'));
    if (elements.length === 0) {
      return;
    }
    root.dataset.revealReady = 'true';
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            (entry.target as HTMLElement).dataset.visible = 'true';
            observer.unobserve(entry.target);
          }
        }
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.08 },
    );
    elements.forEach((element) => observer.observe(element));
    return () => {
      observer.disconnect();
      delete root.dataset.revealReady;
    };
  }, []);

  const toggle = useCallback(() => setEnabled((value) => !value), []);
  const value = useMemo(() => ({ enabled, setEnabled, toggle }), [enabled, toggle]);

  return <MotionContext.Provider value={value}>{children}</MotionContext.Provider>;
}

export function useMotion(): MotionContextValue {
  const context = useContext(MotionContext);
  if (!context) {
    throw new Error('useMotion must be used within MotionProvider');
  }
  return context;
}
