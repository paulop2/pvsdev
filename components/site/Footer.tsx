import Link from 'next/link';
import { footer, identity } from '@/content/site';
import styles from '@/components/site/Footer.module.css';

export default function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.inner}>
        <div className={styles.brand}>
          <Link href="/" className={styles.brandLink}>
            {identity.brand}
          </Link>
          <p className={styles.role}>
            {identity.role} · {identity.location} · {identity.workMode}
          </p>
          <p className={styles.tagline}>{footer.tagline}</p>
        </div>

        {footer.columns.map((column) => (
          <nav key={column.id} className={styles.column} aria-label={column.title}>
            <h3 className={styles.columnTitle}>{column.title}</h3>
            <ul className={styles.columnList}>
              {column.links.map((link) => (
                <li key={link.href}>
                  <Link href={link.href} className={styles.link}>
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>

      <div className={styles.bottom}>
        <p className={styles.copy}>
          © {new Date().getFullYear()} {identity.name}
        </p>
        <a
          className={styles.external}
          href={footer.link.href}
          target="_blank"
          rel="noopener noreferrer"
        >
          {footer.link.label} <span aria-hidden="true">↗</span>
        </a>
      </div>
    </footer>
  );
}
