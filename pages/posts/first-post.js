import Link from 'next/link'
import Image from 'next/image'
import Head from 'next/head'
import Layout from '../../components/layout'
import styles from '../../styles/Home.module.css';


export default function FirstPost() {

  return (
    <Layout>
      <Head>
        <title>First Post</title>
      </Head>

      {/* <h1>Testes</h1> */}

      <div className={styles.grid}>

        <a className={styles.card}>
          <Link href="/" >
            <h2> Back to home</h2>
          </Link>
        </a>


        <a className={styles.card}>
          <Link href="/three/boxes" >
            <h3> Boxes </h3>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/three/birds" >
            <h3> Birds </h3>
          </Link>
        </a>

        <a className={styles.card}>
          <Link href="/posts/art" >
            <h3> Clique aqui </h3>
          </Link>
        </a>

      </div>



    </Layout>
  )
}
