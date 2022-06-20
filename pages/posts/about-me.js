import Link from 'next/link';
import Head from 'next/head';
import Layout from '../../components/layout';
import styles from '../../styles/Home.module.css';

export default function AboutMe() {
  return (
    <Layout>
      <Head>
        <title>Sobre mim</title>
      </Head>

      <div className={styles.grid}>
        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Hobbies </h2>
              <div>
                Desce criança sempre gostei muito de ler, especialmente mangas
                (Japão). Ultimamente, venho lendo muitos Manhuas (China) e
                Manhwas (Coréia).
              </div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Undefeatable Swordsman </h2>
              <div>https://undefeatableswordsman.com/</div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Arcane Sniper </h2>
              <div>https://arcanesniper.com/</div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Mookhyang Dark lady </h2>
              <div>
                https://luminousscans.com/series/1653732347-mookhyang-dark-lady-isekai/
              </div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> A returners magic should be special</h2>
              <div>
                https://flamescans.org/series/1654747321-a-returners-magic-should-be-special/
              </div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Max level hero returner </h2>
              <div>
                https://flamescans.org/series/1654747321-max-level-returner/
              </div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Dungeon reset </h2>
              <div>https://flamescans.org/series/1654747321-dungeon-reset/</div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Kenja no mago </h2>
              <div>https://read.kenjanomago.com/</div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> legend of northern blade</h2>
              <div>https://legendofnorthernblade.com/</div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Volcanic age </h2>
              <div>
                https://luminousscans.com/series/1653732347-volcanic-age/
              </div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2> Volcanic return </h2>
              <div></div>
            </a>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/">
            <a>
              <h2>Descent of the demonic master </h2>
              <div></div>
            </a>
          </Link>
        </a>
      </div>

      <h2>
        <Link href="/">
          <a> &larr; Back to home </a>
        </Link>
      </h2>
    </Layout>
  );
}
