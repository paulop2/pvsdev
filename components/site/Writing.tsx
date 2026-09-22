import Link from 'next/link';
import { sectionMeta, writing } from '@/content/site';
import Section from '@/components/site/Section';
import styles from '@/components/site/Writing.module.css';

export default function Writing() {
  return (
    <Section id="textos" {...sectionMeta.textos}>
      <ul className={styles.list}>
        {writing.map((item) => (
          <li key={item.id} className={styles.row}>
            <Link href={item.href} className={styles.link}>
              <span className={styles.index} aria-hidden="true">
                {item.index}
              </span>
              <span className={styles.body}>
                <span className={styles.title}>{item.title}</span>
                <span className={styles.summary}>{item.summary}</span>
              </span>
              <span className={styles.meta}>{item.type}</span>
              <span className={styles.arrow} aria-hidden="true">
                →
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </Section>
  );
}
