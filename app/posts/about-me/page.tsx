import Link from 'next/link';
import PageShell from '@/components/PageShell';
import styles from '@/styles/Home.module.css';

const manhwas = [
  { name: 'Undefeatable Swordsman', href: 'https://undefeatableswordsman.com/' },
  { name: 'Arcane Sniper', href: 'https://arcanesniper.com/' },
  {
    name: 'Mookhyang Dark lady',
    href: 'https://luminousscans.com/series/1653732347-mookhyang-dark-lady-isekai/',
  },
  {
    name: 'A returners magic should be special',
    href: 'https://flamescans.org/series/1654747321-a-returners-magic-should-be-special/',
  },
  {
    name: 'Max level hero returner',
    href: 'https://flamescans.org/series/1654747321-max-level-returner/',
  },
  { name: 'Dungeon reset', href: 'https://flamescans.org/series/1654747321-dungeon-reset/' },
  { name: 'Kenja no mago', href: 'https://read.kenjanomago.com/' },
  { name: 'legend of northern blade', href: 'https://legendofnorthernblade.com/' },
  { name: 'Volcanic age', href: 'https://luminousscans.com/series/1653732347-volcanic-age/' },
  { name: 'Volcanic return', href: '' },
  { name: 'Descent of the demonic master', href: '' },
];

export const metadata = { title: 'Sobre mim' };

export default function AboutMe() {
  return (
    <PageShell>
      <div className={styles.grid}>
        <div className={styles.card}>
          <h2>Hobbies</h2>
          <div>
            Desce criança sempre gostei muito de ler, especialmente mangas (Japão).
            Ultimamente, venho lendo muitos Manhuas (China) e Manhwas (Coréia).
          </div>
        </div>

        {manhwas.map((item) => (
          <a key={item.name} href={item.href} className={styles.card}>
            <h2>{item.name}</h2>
            {item.href ? <div>{item.href}</div> : null}
          </a>
        ))}
      </div>

      <h2>
        <Link href="/">&larr; Back to home</Link>
      </h2>
    </PageShell>
  );
}
