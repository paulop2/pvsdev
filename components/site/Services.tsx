import { sectionMeta, services } from '@/content/site';
import Section from '@/components/site/Section';
import styles from '@/components/site/Services.module.css';

export default function Services() {
  return (
    <Section id="atuacao" {...sectionMeta.atuacao}>
      <ul className={styles.grid}>
        {services.map((service) => (
          <li key={service.id} className={styles.card}>
            <div className={styles.top}>
              <span className={styles.glyph} aria-hidden="true">
                ◆
              </span>
              <span className={styles.index}>{service.index}</span>
            </div>
            <h3 className={styles.name}>{service.title}</h3>
            <p className={styles.desc}>{service.description}</p>
            <ul className={styles.tags}>
              {service.tags.map((tag) => (
                <li key={tag} className={styles.tag}>
                  {tag}
                </li>
              ))}
            </ul>
            {service.learning ? <p className={styles.badge}>Em aprendizado</p> : null}
          </li>
        ))}
      </ul>
    </Section>
  );
}
