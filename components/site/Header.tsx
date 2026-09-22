'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { chatCta, identity, navItems } from '@/content/site';
import { useMotion } from '@/components/site/MotionProvider';
import styles from '@/components/site/Header.module.css';

export default function Header() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const [announcement, setAnnouncement] = useState('');
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const { enabled, toggle } = useMotion();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    if (!open) {
      return;
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setOpen(false);
        buttonRef.current?.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  }, [open]);

  return (
    <header className={`${styles.header} ${scrolled ? styles.scrolled : ''}`}>
      <p className="srOnly" role="status" aria-live="polite">
        {announcement}
      </p>
      <div className={styles.inner}>
        <Link href="/" className={styles.brand} aria-label={`${identity.name} — início`}>
          <span className={styles.brandMark} aria-hidden="true">
            &gt;
          </span>
          {identity.brand}
        </Link>

        <nav className={styles.nav} aria-label="Seções">
          {navItems.map((item) => (
            <Link key={item.id} href={item.href} className={styles.navLink}>
              {item.label}
            </Link>
          ))}
        </nav>

        <div className={styles.right}>
          <button
            type="button"
            className={styles.motion}
            aria-pressed={!enabled}
            aria-label={enabled ? 'Desativar movimento' : 'Ativar movimento'}
            onClick={() => {
              toggle();
              setAnnouncement(enabled ? 'Movimento desativado.' : 'Movimento ativado.');
            }}
          >
            <span
              className={styles.motionDot}
              data-on={enabled ? 'true' : undefined}
              aria-hidden="true"
            />
            <span className={styles.motionLabel}>Movimento</span>
          </button>
          <Link href={chatCta.href} className={styles.chatPill}>
            {chatCta.label}
          </Link>
          <button
            ref={buttonRef}
            type="button"
            className={styles.burger}
            aria-expanded={open}
            aria-controls="mobile-nav"
            aria-label={open ? 'Fechar menu' : 'Abrir menu'}
            onClick={() => setOpen((value) => !value)}
          >
            <span className={open ? styles.barOpenTop : styles.bar} />
            <span className={open ? styles.barOpenBottom : styles.bar} />
          </button>
        </div>
      </div>

      {open && (
        <div className={styles.overlay} id="mobile-nav">
          <nav className={styles.overlayNav} aria-label="Seções">
            {navItems.map((item, index) => (
              <Link
                key={item.id}
                href={item.href}
                className={styles.overlayLink}
                style={{ '--delay': `${index * 40}ms` } as React.CSSProperties}
                onClick={() => setOpen(false)}
                autoFocus={index === 0}
              >
                <span className={styles.overlayIndex} aria-hidden="true">
                  {String(index + 1).padStart(2, '0')}
                </span>
                {item.label}
              </Link>
            ))}
            <Link
              href={chatCta.href}
              className={styles.overlayLink}
              style={{ '--delay': `${navItems.length * 40}ms` } as React.CSSProperties}
              onClick={() => setOpen(false)}
            >
              <span className={styles.overlayIndex} aria-hidden="true">
                {String(navItems.length + 1).padStart(2, '0')}
              </span>
              Chat
            </Link>
          </nav>
        </div>
      )}
    </header>
  );
}
