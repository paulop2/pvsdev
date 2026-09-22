import Link from 'next/link';
import { hero, identity } from '@/content/site';
import BlackHoleStage from '@/components/site/BlackHoleStage';
import styles from '@/components/site/Hero.module.css';

const codeLines = [
  "import { ship } from '@pvs/edge';",
  '',
  'const stack = [',
  "  'typescript',",
  "  'react',",
  "  'workers',",
  '];',
  '',
  'export function build(product: Product) {',
  '  return ship(product, { edge: true });',
  '}',
];

export default function Hero() {
  return (
    <section className={styles.hero} id="top" aria-labelledby="hero-title">
      <pre className={styles.code} aria-hidden="true">
        {codeLines.join('\n')}
      </pre>

      <div className={styles.inner}>
        <div className={styles.copy}>
          <p className={styles.intro}>
            {hero.greeting} <span className={styles.name}>{identity.firstName}</span>
          </p>

          <h1 className={styles.title} id="hero-title">
            {hero.headline.map((line, index) => (
              <span
                key={line}
                className={index === hero.accentLine ? styles.accentLine : styles.titleLine}
              >
                {line}
              </span>
            ))}
          </h1>

          <p className={styles.kicker}>{hero.kicker}</p>

          <p className={styles.description}>{hero.description}</p>

          <div className={styles.ctas}>
            {hero.ctas.map((cta) => (
              <Link
                key={cta.id}
                href={cta.href}
                className={`${styles.cta} ${styles[cta.variant]}`}
              >
                {cta.label}
              </Link>
            ))}
          </div>
        </div>

        <div className={styles.visual}>
          <BlackHoleStage />
        </div>
      </div>
    </section>
  );
}
