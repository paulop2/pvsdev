import Link from 'next/link';
import PageShell from '@/components/PageShell';
import styles from '@/styles/Home.module.css';

export const metadata = { title: 'Rant' };

export default function Rant() {
  return (
    <PageShell>
      <div className={styles.grid}>
        <div className={styles.card}>
          <h2>Inoue</h2>
          <div>
            Seguir em frente é como tatear no escuro. <br />
            A luz que brilha ao longe é frágil e incerta. <br />
            Mas a luz interna, essa sim, se agita loucamente. <br />
            Quero sempre me sentir desse jeito. <br />
          </div>
        </div>
      </div>

      <h2>
        <Link href="/">&larr; Back to home</Link>
      </h2>
    </PageShell>
  );
}
