import Link from 'next/link';
import styles from '@/styles/Home.module.css';

export default function Home() {
  return (
    <div className={styles.container}>
      <main className={styles.main}>
        <h1 className={styles.title}>Paulo Vitor Souza</h1>

        <p className={styles.description}>Software Developer</p>

        <div className={styles.grid}>
          <a href="" className={styles.card}>
            <h3>Portfolio &rarr;</h3>
            <p>Veja os projetos que participei</p>
            <p>-- em breve --</p>
          </a>

          <Link href="/chat" className={styles.card}>
            <h3>Chat &rarr;</h3>
            <p>Converse com meu assistente de IA.</p>
          </Link>

          <div className={styles.card}>
            <h3>RAG &rarr;</h3>
            <p>Veja o pipeline de retrieval ao vivo.</p>
            <p>-- em breve --</p>
          </div>

          <Link href="/posts/rants" className={styles.card}>
            <h3>Rants &rarr;</h3>
            <p>Discutindo sobre tudo e todos.</p>
          </Link>

          <Link href="/posts/about-me" className={styles.card}>
            <h3>Sobre mim &rarr;</h3>
            <p>Descubra mais sobre mim.</p>
          </Link>

          <Link href="/posts/first-post" className={styles.card}>
            <h3>Testes &rarr;</h3>
            <p>Testes realizados com three.js e outras tecnologias</p>
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
