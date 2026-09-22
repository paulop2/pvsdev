import styles from '@/components/site/BlackHoleFallback.module.css';

export default function BlackHoleFallback() {
  return (
    <svg
      className={styles.fallback}
      viewBox="0 0 800 800"
      role="presentation"
      focusable="false"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <radialGradient id="bhCore" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#000000" />
          <stop offset="62%" stopColor="#000000" />
          <stop offset="100%" stopColor="#03170b" />
        </radialGradient>
        <linearGradient id="bhDisk" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="#15803d" />
          <stop offset="30%" stopColor="#4ade80" />
          <stop offset="52%" stopColor="#00ff41" />
          <stop offset="74%" stopColor="#4ade80" />
          <stop offset="100%" stopColor="#15803d" />
        </linearGradient>
        <filter id="bhGlow" x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur stdDeviation="7" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
        <filter id="bhSoft" x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur stdDeviation="16" />
        </filter>
      </defs>

      <g fill="#4ade80">
        <circle cx="128" cy="150" r="1.6" opacity="0.7" />
        <circle cx="660" cy="120" r="1.3" opacity="0.5" />
        <circle cx="700" cy="430" r="1.8" opacity="0.6" />
        <circle cx="150" cy="560" r="1.4" opacity="0.45" />
        <circle cx="560" cy="690" r="1.5" opacity="0.5" />
        <circle cx="330" cy="96" r="1.1" opacity="0.4" />
        <circle cx="232" cy="672" r="1.2" opacity="0.35" />
        <circle cx="740" cy="250" r="1.1" opacity="0.4" />
      </g>

      <ellipse
        cx="400"
        cy="400"
        rx="300"
        ry="96"
        fill="none"
        stroke="#00ff41"
        strokeWidth="26"
        opacity="0.16"
        transform="rotate(-18 400 400)"
        filter="url(#bhSoft)"
      />

      <g transform="rotate(-18 400 400)" filter="url(#bhGlow)">
        <ellipse
          cx="400"
          cy="400"
          rx="286"
          ry="84"
          fill="none"
          stroke="url(#bhDisk)"
          strokeWidth="9"
          opacity="0.92"
        />
        <ellipse
          cx="400"
          cy="400"
          rx="236"
          ry="66"
          fill="none"
          stroke="#86efac"
          strokeWidth="2.5"
          opacity="0.55"
        />
      </g>

      <circle cx="400" cy="400" r="122" fill="url(#bhCore)" />
      <circle
        cx="400"
        cy="400"
        r="122"
        fill="none"
        stroke="rgba(0,255,65,0.55)"
        strokeWidth="2"
      />
      <path
        d="M 296 322 A 132 132 0 0 1 504 322"
        fill="none"
        stroke="#00ff41"
        strokeWidth="3"
        strokeLinecap="round"
        opacity="0.8"
        filter="url(#bhGlow)"
      />
    </svg>
  );
}
