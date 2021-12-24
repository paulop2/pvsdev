import Link from 'next/link'
import Head from 'next/head'
import Layout from '../../components/layout'
import styles from '../../styles/Home.module.css';

export default function Rant() {

  return (
    <Layout>
      <Head>
        <title>Rant</title>
      </Head>

      <div className={styles.grid}>

        <a className={styles.card}>
          <Link href="/" >
            <a >
              <h2> Inoue </h2>
              <div>
                Seguir em frente é como tatear no escuro. <br />
                A luz que brilha ao longe é frágil e incerta. <br />
                Mas a luz interna, essa sim, se agita loucamente. <br />
                Quero sempre me sentir desse jeito. <br />
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

