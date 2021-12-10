import Link from 'next/link'
import Head from 'next/head'
import Layout from '../../components/layout'
import styles from '../../styles/Home.module.css';

export default function AboutMe() {

  return (
    <Layout>
      <Head>
        <title>Sobre mim</title>
      </Head>

      <div className={styles.grid}>

        <a className={styles.card}>
          <Link href="/" >
            <a >
              <h2> Hobbies </h2>
              <div>
                Desce criança sempre gostei muito de ler, especialmente mangas (Japão).
                Ultimamente, venho lendo muitos Manhuas (China) e Manhwas (Coréia).
              </div>
            </a>
          </Link>
        </a>

      </div>


      <h2>
        <Link href="/" >
          <a> &larr; Back to home </a>
        </Link>
      </h2>

    </Layout>
  )
}
