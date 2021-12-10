import Head from 'next/head';
import Link from 'next/link';
import styles from '../styles/Home.module.css';

export default function Home() {
  return (
    <div className={styles.container}>
      <Head>
        <title>PVS DEV</title>
        <link rel="icon" href="/favicon.ico" />
      </Head>

      <main className={styles.main}>
        <h1 className={styles.title}>
          Paulo Vitor Souza
        </h1>

        <p className={styles.description}>
          Software Developer
        </p>

        <div className={styles.grid}>
          <a href="" className={styles.card}>
            <h3>Portfolio &rarr;</h3>
            <p>Veja os projetos que participei</p>
            <p>-- em breve --</p>
          </a>

          <Link href="/posts/rants">
            <a className={styles.card}>
              <h3>Rants &rarr;</h3>
              <p>Discutindo sobre tudo e todos.</p>
            </a>
          </Link>


          <Link href="/posts/about-me">
            <a className={styles.card}>
              <h3>Sobre mim &rarr;</h3>
              <p>Descubra mais sobre mim.</p>
            </a>
          </Link>

          <Link href="/posts/first-post"  >
            <a className={styles.card}>
              <h3>Testes &rarr;</h3>
              <p>
                Testes realizados com three.js e outras tecnologias
              </p>
            </a>
          </Link>
        </div>
      </main>

      <footer className={styles.footer}>
        <a
          href="https://www.youtube.com/watch?v=pVpMWi-x1GY"
          target="_blank"
          rel="noopener noreferrer"
        >
          Quero me tornar uma pessoa gentil
        </a>
      </footer>
    </div>
  );
}
