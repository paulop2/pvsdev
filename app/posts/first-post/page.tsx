import Link from 'next/link';
import PageShell from '@/components/PageShell';
import styles from '@/styles/Home.module.css';

export const metadata = { title: 'First Post' };

export default function FirstPost() {
  return (
    <PageShell>
      <div className={styles.grid}>
        <Link href="/" className={styles.card}>
          <h2>Back to home</h2>
        </Link>

        <Link href="/three/boxes" className={styles.card}>
          <h3>Boxes</h3>
        </Link>

        <Link href="/posts/art" className={styles.card}>
          <h3>Clique aqui</h3>
        </Link>
      </div>
    </PageShell>
  );
}
