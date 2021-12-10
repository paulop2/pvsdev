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

      <h1>First Post</h1>

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

        <a href="https://nextjs.org/docs" className={styles.card}>
          <h3>Documentation &rarr;</h3>
          <p>Find in-depth information about Next.js features and API.</p>
        </a>


      </div>


      <h2>
        <Link href="/" >
          <a> Back to home</a>
        </Link>
      </h2>


      <Image
        src="/images/profile.jpg" // Route of the image file
        height={200} // Desired size with correct aspect ratio
        width={200} // Desired size with correct aspect ratio
        alt="Your Name"
      />
    </Layout>
  )
}
